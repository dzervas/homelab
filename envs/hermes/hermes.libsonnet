// Hermes itself: the Signal gateway, the dashboard and signal-cli in one pod.
// It holds the LLM route, the Signal account and the 1Password token for
// website logins, but runs no agent commands: the terminal, file tools and
// execute_code go over SSH to the workspace (workspace.libsonnet).
local externalSecrets = import 'external-secrets.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local browser = import './browser.libsonnet';
local mcp = import './mcp.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local namespace = 'hermes';
local domain = 'hermes.vpn.dzerv.art';
local image = 'git.vpn.dzerv.art/dzervas/homelab/hermes:latest';  // docker/hermes
local managedDir = '/etc/hermes-managed';
local sshKey = '/opt/data/.workspace-ssh/id_ed25519';

// Gateway and dashboard share one container: gVisor gives each container its
// own view of the volume, so SQLite locks across containers don't see each
// other and state.db gets corrupted. s6 would supervise both but needs root.
// The loop restarts the gateway after it exits; --external-supervisor makes
// the dashboard's restart and `hermes update` hand the restart to this loop.
// SSH ControlMaster hard-links its socket, which gVisor's 9p volumes reject, and
// Hermes hardcodes its dir under TMPDIR (the scratch dir on the PV), so that dir
// is a symlink into /tmp. The hourly touch keeps scratch pruning (24h idle) off it
local supervisor = |||
  stop() { kill -TERM $(jobs -p) 2>/dev/null; wait; }
  trap 'stop; exit 0' TERM INT
  rm -rf /opt/data/cache/scratch/hermes-ssh
  mkdir -p /tmp/hermes-ssh
  ln -s /tmp/hermes-ssh /opt/data/cache/scratch/hermes-ssh
  while sleep 3600; do touch -h /opt/data/cache/scratch/hermes-ssh; done &
  (
    trap 'kill -TERM $gw 2>/dev/null; wait $gw; exit 0' TERM
    while :; do hermes gateway run --external-supervisor & gw=$!; wait $gw; sleep 1; done
  ) &
  hermes dashboard --host 0.0.0.0 --port 9119 --no-open --skip-build &
  wait -n
  stop
  exit 1
|||;

// Hermes' managed scope: merged over ~/.hermes/config.yaml, and these keys
// can't be changed from inside Hermes. Everything else stays Hermes' own
local managedConfig = {
  custom_providers: [{
    name: 'CPA',
    base_url: 'http://cliproxyapi.cliproxyapi.svc:8317/v1',
    // CPA has no API keys; without one Hermes warns on every auxiliary call
    api_key: 'sk-dummy',
    model: 'gpt-6-luna',
    api_mode: 'chat_completions',
  }],
  database: { journal_mode: 'delete' },  // Hermes nags about SQLite WAL on virtiofs and results in corruption
  secrets: { onepassword: { enabled: true } },
  terminal: { backend: 'ssh' },
  browser: {
    cdp_url: browser.cdpUrl,
    // The built-in browser_* tools talk CDP from this pod (and fill logins
    // from the vault). The default Browser Use driver would run through the
    // terminal, i.e. in the workspace
    backend: 'off',
  },
  dashboard: {
    // Also the only Host the dashboard's DNS-rebinding guard accepts
    public_url: 'https://' + domain,
    // Public PKCE client, magicentry names it kube-<magicentry.rs/name>
    oauth: {
      provider: 'self-hosted',
      self_hosted: { issuer: 'https://auth.dzerv.art', client_id: 'kube-Hermes' },
    },
  },
  mcp_servers: mcp.config,
};

{
  hermes:
    lab.new('hermes', image)
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    // The image's own hermes user: the one non-root UID its bootstrap accepts
    + lab.withRunAsUser(10000)
    + lab.withAffinity(affinity.requireProviders(['homelab']))
    + lab.withPV('/opt/data', { name: 'data', size: '10Gi' })
    // The entrypoint's bootstrap runs first, then execs bash
    + lab.withArgs(['bash', '-c', supervisor])
    + lab.withVpnHttp(9119, domain)
    + lab.withPodLabels({ 'ai/enable': 'true' })  // see envs/cliproxyapi networkPolicy
    + lab.withConfigMapMount(managedDir, 'hermes-managed')
    + lab.withExternalSecretMount('workspace-ssh', '/etc/workspace-ssh', { store: '1password', remoteKey: 'hermes-workspace-ssh' })
    // 1Password item `hermes`: op-service-account-token (can read only the
    // hermes-logins vault), signal-account (E.164), signal-allowed-users
    + lab.withExternalSecretEnvs('hermes-op', {
      OP_SERVICE_ACCOUNT_TOKEN: 'op-service-account-token',
      SIGNAL_ACCOUNT: 'signal-account',
      SIGNAL_ALLOWED_USERS: 'signal-allowed-users',
      MATRIX_PASSWORD: 'matrix-password',
      MATRIX_RECOVERY_KEY: 'matrix-recovery-key',
      MATRIX_ALLOWED_USERS: 'matrix-allowed-users',
      MATRIX_USER_ID: 'matrix-user-id',
      MATRIX_DEVICE_ID: 'matrix-device-id',
    }, { store: '1password', remoteKey: 'hermes' })
    // Hosted MCP servers' bearer tokens (mcp.libsonnet)
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
      HERMES_MANAGED_DIR: managedDir,
      // Browser readers skip the managed overlay; the CDP env override takes precedence
      BROWSER_CDP_URL: browser.cdpUrl,
      SIGNAL_HTTP_URL: 'http://127.0.0.1:8080',
      TERMINAL_ENV: 'ssh',
      TERMINAL_SSH_HOST: 'workspace.hermes-workspace.svc',
      TERMINAL_SSH_USER: 'agent',  // passwordless sudo
      TERMINAL_SSH_KEY: sshKey,

      MATRIX_HOMESERVER: 'https://matrix.org',
      MATRIX_AUTO_THREAD: 'true',
      MATRIX_DM_AUTO_THREAD: 'true',
      MATRIX_E2EE_MODE: 'required',
    })
    + lab.withResources({ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } })
    // ssh refuses keys that aren't private to their owner; secret mounts are
    // root-owned
    + lab.withInitContainer({
      name: 'ssh-key',
      image: image,
      command: ['sh', '-c', 'install -d -m 700 %s && install -m 600 /etc/workspace-ssh/private_key %s' % [std.split(sshKey, '/id_')[0], sshKey]],
    })
    // Multi-account mode (no -a); Hermes passes the account. --no-receive-stdout
    // keeps message bodies out of the logs
    + lab.withContainer({
      name: 'signal-cli',
      image: 'registry.gitlab.com/packaging/signal-cli/signal-cli-jre:latest',
      args: ['--config', '/opt/data/signal-cli', '--scrub-log', 'daemon', '--http', '127.0.0.1:8080', '--no-receive-stdout'],
    })
    + {
      workload+: { spec+: { template+: { spec+: {
        // Not PID 1, so the entrypoint skips s6-overlay (which needs root);
        // the pause container reaps zombies
        shareProcessNamespace: true,
        runtimeClassName: 'gvisor',
        // A Service named hermes would inject HERMES_* service-link env vars
        enableServiceLinks: false,
        automountServiceAccountToken: false,
        securityContext+: {
          seccompProfile: { type: 'RuntimeDefault' },
          // The PV is already owned by the hermes UID; fsGroup's recursive chmod
          // (g+rw on every file) breaks tools that insist on 0600, like op
          fsGroup:: null,
          fsGroupChangePolicy:: null,
        },
      } } } },

      // Registers the dashboard with magicentry as an OIDC client (admin realm)
      service+: {
        metadata+: {
          labels+: { 'magicentry.rs/enable': 'true' },
          annotations+: {
            'magicentry.rs/name': 'Hermes',
            'magicentry.rs/url': 'https://' + domain,
            'magicentry.rs/realms': 'admin',
            'magicentry.rs/oidc_redirect_urls': 'https://%s/auth/callback' % domain,
          },
        },
      },
    },

  managed:
    k.core.v1.configMap.new('hermes-managed', { 'config.yaml': std.manifestYamlDoc(managedConfig) })
    + k.core.v1.configMap.metadata.withNamespace(namespace),

  egress: netpol.egress('hermes-egress', namespace, { 'app.kubernetes.io/name': 'hermes' }, {
    // The browser's SSRF guard resolves navigation targets from this pod before using CDP
    dnsNames: ['*'],
    cidrs: [netpol.internet],
    endpoints: [
      { namespace: 'cliproxyapi', labels: { 'app.kubernetes.io/name': 'cliproxyapi' }, ports: [{ port: 8317 }] },
      { namespace: 'hermes-workspace', labels: { 'app.kubernetes.io/name': 'workspace' }, ports: [{ port: 22 }] },
      { namespace: namespace, labels: { 'app.kubernetes.io/name': 'browser' }, ports: [{ port: 9222 }] },
    ] + mcp.hermesEgress.endpoints,
    // auth.dzerv.art (dashboard OIDC token/JWKS calls) resolves to the nodes'
    // public IPs, which Cilium identifies as host/remote-node, not by FQDN
    entities: [{ entities: ['host', 'remote-node'], ports: [{ port: 443 }] }],
  }),

  // Only Traefik, for the dashboard
  ingress: netpol.onlyFromNamespaces('hermes-ingress', namespace, { 'app.kubernetes.io/name': 'hermes' }, ['traefik']),
}
