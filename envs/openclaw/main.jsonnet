local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local cnp = cilium.cilium.v2.ciliumNetworkPolicy;

local namespace = 'openclaw';
local domain = 'claw.vpn.dzerv.art';
local image = 'git.vpn.dzerv.art/dzervas/homelab/openclaw:latest';
local labels = { 'app.kubernetes.io/name': 'openclaw' };
local nsKey = 'k8s:io.kubernetes.pod.namespace';

// Bootstrap once: subsequent UI/agent config edits survive restarts
local config = {
  gateway: {
    mode: 'local',
    bind: 'lan',
    port: 18789,
    publicOrigin: 'https://' + domain,
    // Dynamic Traefik pod addresses; ingress below rejects other pod identities.
    // Verify the live proxy source before first use; node/root admins remain trusted
    trustedProxies: ['10.200.0.0/16'],
    auth: {
      mode: 'trusted-proxy',
      trustedProxy: {
        userHeader: 'x-remote-user',
        requiredHeaders: ['x-forwarded-proto', 'x-forwarded-host'],
        allowLoopback: false,
        // Magicentry's admin realm gates access; separate human identities share
        // the Family agent. Approve each browser device once using the local CLI
        deviceAutoApprove: { enabled: false },
      },
    },
  },
  agents: {
    defaults: {
      workspace: '/data/.openclaw/workspace',
      model: { primary: 'cliproxyapi/gpt-6-luna' },
      // The whole pod is gVisor-isolated; no Docker socket or SSH workspace
      sandbox: { mode: 'off' },
    },
    entries: { main: { name: 'Family', default: true } },
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
  tools: { profile: 'full', exec: { host: 'gateway' } },
  browser: {
    enabled: true,
    headless: true,
    noSandbox: false,  // Chromium's nested sandbox cannot run inside gVisor
    // OpenClaw launches Chromium itself, bypassing Patchright's launch flags
    extraArgs: ['--disable-blink-features=AutomationControlled'],
  },
};

local start = |||
  umask 077
  mkdir -p "$OPENCLAW_STATE_DIR" "$HOME/.config/op" "$HOME/.npm-global"
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    install -m 600 /etc/openclaw-bootstrap/openclaw.json "$OPENCLAW_CONFIG_PATH"
  fi
  # Preserve the official entrypoint's retained-volume migrations after seeding
  exec node /app/docker-entrypoint.mjs node /app/openclaw.mjs gateway
|||;

// Exec probes avoid opening a second ingress path around the trusted proxy
local probe(path) = {
  exec: { command: ['node', '-e', "fetch('http://127.0.0.1:18789/%s').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))" % path] },
  timeoutSeconds: 5,
  periodSeconds: 30,
};

{
  openclaw:
    lab.new('openclaw', image)
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({ forgejoCreds: 'enabled' })
    + lab.withImagePullSecrets(['forgejo-cluster-secret'])
    + lab.withType('StatefulSet')
    + lab.withAffinity(affinity.requireProviders(['homelab']))
    + lab.withServiceName('openclaw')
    + lab.withPV('/data', { name: 'data', size: '20Gi' })
    + lab.withVpnHttp(18789, domain, magicentry={ name: 'OpenClaw', realms: 'agent' })
    + lab.withPodLabels({ 'ai/enable': 'true' })
    + lab.withConfigMapMount('/etc/openclaw-bootstrap', 'openclaw-bootstrap')
    + lab.withArgs(['sh', '-ec', start])
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

  egress: netpol.egress('openclaw-egress', namespace, labels, {
    dnsNames: ['*'],
    cidrs: [netpol.internet],
    endpoints: [{ namespace: 'cliproxyapi', labels: { 'app.kubernetes.io/name': 'cliproxyapi' }, ports: [{ port: 8317 }] }],
  }),

  ingress:
    cnp.new('openclaw-ingress')
    + cnp.metadata.withNamespace(namespace)
    + cnp.spec.endpointSelector.withMatchLabels(labels)
    + cnp.spec.withIngress([{
      fromEndpoints: [{ matchLabels: { [nsKey]: 'traefik', 'k8s:app.kubernetes.io/name': 'traefik' } }],
      toPorts: [{ ports: [{ port: '18789', protocol: 'TCP' }] }],
    }])
    // Deny wins over envs/network's additive allows, blocking pod header spoofing.
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
