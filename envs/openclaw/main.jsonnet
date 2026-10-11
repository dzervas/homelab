local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local mcp = import '../mcp/main.jsonnet';

local cnp = cilium.cilium.v2.ciliumNetworkPolicy;
local password = externalSecrets.generators.v1alpha1.password;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local namespace = 'openclaw';
local domain = 'claw.vpn.dzerv.art';
local authSecretName = 'openclaw-auth';
local image = 'ghcr.io/openclaw/openclaw:latest-browser';
local labels = { 'app.kubernetes.io/name': 'openclaw' };
local nsKey = 'k8s:io.kubernetes.pod.namespace';

// Bootstrap once; shared MCP entries are refreshed on startup, other UI/agent edits survive
// Existing PVCs must set gateway.auth to { mode: 'token' } before this rollout
local config = {
  gateway: {
    mode: 'local',
    bind: 'lan',
    port: 18789,
    publicOrigin: 'https://' + domain,
    // Forwarded client attribution still needs Traefik trust in token mode
    trustedProxies: ['10.200.0.0/16'],
    allowRealIpFallback: true,
    // Token comes from OPENCLAW_GATEWAY_TOKEN, not the persisted config
    auth: { mode: 'token' },
  },
  models: {
    providers: {
      cliproxyapi: {
        baseUrl: 'http://cliproxyapi.cliproxyapi.svc:8317/v1',
        apiKey: 'sk-dummy',
        api: 'openai-completions',
        models: [{ id: 'gpt-6-luna', name: 'GPT-6 Luna', reasoning: true, input: ['text', 'image'] }],
      },
    },
  },
  mcp: {
    servers: {
      [name]: mcp.config[name] { transport: 'streamable-http', enabled: true }
      for name in std.objectFields(mcp.config)
    },
  },
  browser: {
    enabled: true,
    headless: true,
    noSandbox: false,  // Chromium's nested sandbox cannot run inside gVisor
    // OpenClaw launches Chromium itself, bypassing Patchright's launch flags
    extraArgs: ['--disable-blink-features=AutomationControlled'],
  },

  plugins: { entries: { 'device-pair': { config: { publicUrl: 'wss://' + domain } } } },
};

local start = |||
  umask 077
  mkdir -p "$OPENCLAW_STATE_DIR" "$HOME/.config/op" "$HOME/.npm-global"
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    install -m 600 /etc/openclaw-bootstrap/openclaw.json "$OPENCLAW_CONFIG_PATH"
  fi
  # Refresh managed MCP entries on retained volumes without replacing user settings
  node --input-type=commonjs <<'NODE'
  const fs = require('node:fs');
  const path = process.env.OPENCLAW_CONFIG_PATH;
  const config = JSON.parse(fs.readFileSync(path, 'utf8'));
  const managed = JSON.parse(fs.readFileSync('/etc/openclaw-bootstrap/openclaw.json', 'utf8'));
  config.mcp = { ...config.mcp, servers: { ...config.mcp?.servers, ...managed.mcp.servers } };
  fs.writeFileSync(path, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
  NODE
  # Restore private permissions after fsGroup handling on the retained volume
  printf '%s\n' "$GIT_CREDENTIALS" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  git config --global credential.helper store
  # Preserve the official entrypoint's retained-volume migrations after seeding
  exec node /app/docker-entrypoint.mjs node /app/openclaw.mjs gateway
|||;

// Keep health checks local rather than opening another ingress path
local probe(path) = {
  exec: { command: ['node', '-e', "fetch('http://127.0.0.1:18789/%s').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))" % path] },
  timeoutSeconds: 5,
  periodSeconds: 30,
};

{
  openclaw:
    lab.new('openclaw', image)
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({
      forgejoCreds: 'enabled',
      'pod-security.kubernetes.io/enforce': 'restricted',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    })
    + lab.withImagePullSecrets(['forgejo-cluster-secret'])
    + lab.withType('StatefulSet')
    + lab.withAffinity(affinity.requireProviders(['homelab']))
    + lab.withServiceName('openclaw')
    + lab.withPV('/data', { name: 'data', size: '20Gi' })
    + lab.withVpnHttp(18789, domain)
    + lab.withPodLabels({ 'ai/enable': 'true', 'mcp/enable': 'true' })
    + lab.withConfigMapMount('/etc/openclaw-bootstrap', 'openclaw-bootstrap')
    + lab.withArgs(['sh', '-ec', start])
    + lab.withSecretEnv({ OPENCLAW_GATEWAY_TOKEN: { name: authSecretName, key: 'token' } })
    // Reuse the Forgejo bot credentials previously supplied to Hermes' workspace
    + lab.withExternalSecretEnvs('openclaw-git', { GIT_CREDENTIALS: 'git-credentials' }, {
      store: '1password',
      remoteKey: 'hermes-workspace',
    })
    + std.foldl(
      function(acc, env) acc + lab.withExternalSecretEnvs(mcp.tokens[env][0] + '-op', { [env]: mcp.tokens[env][1] }, {
        store: '1password',
        remoteKey: mcp.tokens[env][0],
      }),
      std.objectFields(mcp.tokens),
      {},
    )
    + lab.withEnv({
      TZ: timezone,
      HOME: '/data',
      OPENCLAW_STATE_DIR: '/data/.openclaw',
      OPENCLAW_CONFIG_PATH: '/data/.openclaw/openclaw.json',
      XDG_CONFIG_HOME: '/data/.config',
      npm_config_prefix: '/data/.npm-global',
      PATH: '/data/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
      // Keep the image's browser cache visible after moving HOME to the PVC
      PLAYWRIGHT_BROWSERS_PATH: '/home/node/.cache/ms-playwright',
    })
    + lab.withStartupProbe(probe('startupz') + { periodSeconds: 10, failureThreshold: 60 })
    + lab.withReadinessProbe(probe('readyz'))
    + lab.withLivenessProbe(probe('healthz'))
    + lab.withPodSecurityContext({ seccompProfile: { type: 'RuntimeDefault' } })
    + {
      workload+: { spec+: { template+: { spec+: {
        // Existing cluster RuntimeClass, registered by envs/hermes
        runtimeClassName: 'gvisor',
        enableServiceLinks: false,
        automountServiceAccountToken: false,
      } } } },
    },

  bootstrap:
    k.core.v1.configMap.new('openclaw-bootstrap', { 'openclaw.json': std.manifestJsonEx(config, '  ') })
    + k.core.v1.configMap.metadata.withNamespace(namespace),

  tokenGenerator:
    password.new(authSecretName)
    + password.metadata.withNamespace(namespace)
    + password.spec.withLength(64)
    + password.spec.withSymbols(0)
    + password.spec.withAllowRepeat(true),

  auth:
    externalSecret.new(authSecretName)
    + externalSecret.metadata.withNamespace(namespace)
    // Avoid automatic rotation: the Gateway reads its environment at startup
    + externalSecret.spec.withRefreshPolicy('CreatedOnce')
    + externalSecret.spec.target.template.withEngineVersion('v2')
    + externalSecret.spec.target.template.withData({ token: '{{ .password }}' })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          name: authSecretName,
        },
      },
    }]),

  egress: netpol.egress('openclaw-egress', namespace, labels, {
    dnsNames: ['*'],
    cidrs: [netpol.internet],
    endpoints: [
      { namespace: 'cliproxyapi', labels: { 'app.kubernetes.io/name': 'cliproxyapi' }, ports: [{ port: 8317 }] },
      netpol.traefikVpn,  // git.vpn.dzerv.art resolves to Traefik's private VPN address
    ] + mcp.clientEgress.endpoints,
    fqdns: mcp.clientEgress.fqdns,
  }),

  ingress:
    cnp.new('openclaw-ingress')
    + cnp.metadata.withNamespace(namespace)
    + cnp.spec.endpointSelector.withMatchLabels(labels)
    + cnp.spec.withIngress([{
      fromEndpoints: [{ matchLabels: { [nsKey]: 'traefik', 'k8s:app.kubernetes.io/name': 'traefik' } }],
      toPorts: [{ ports: [{ port: '18789', protocol: 'TCP' }] }],
    }])
    // Deny wins over envs/network's additive allows, keeping access behind Traefik.
    // Cilium's default allowLocalhost can bypass policy for the local node; do not
    // treat this as isolation from host-network processes or node/root admins
    + cnp.spec.withIngressDeny([
      { fromEntities: ['world', 'host', 'remote-node', 'ingress', 'unmanaged', 'init', 'health', 'kube-apiserver'] },
      { fromEndpoints: [
        { matchExpressions: [{ key: nsKey, operator: 'NotIn', values: ['traefik'] }] },
        {
          matchLabels: { [nsKey]: 'traefik' },
          matchExpressions: [{ key: 'k8s:app.kubernetes.io/name', operator: 'NotIn', values: ['traefik'] }],
        },
      ] },
    ]),
}
