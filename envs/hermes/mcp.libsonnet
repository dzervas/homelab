// MCP servers Hermes connects to. To add one, add an entry to `servers`:
//
//   Hosted (someone else runs it):
//     name: { url: 'https://…/mcp', fqdn: 'host', token: true }   token: send a bearer token
//   Self-hosted (a pod in the mcp namespace, speaking streamable HTTP on /mcp):
//     name: { image: '…:latest', port: 8080, args: [], env: {}, secrets: { ENV: 'field' },
//             egress: netpol.egress opts, arch: 'amd64' }
//
// Tokens and secrets come from the 1Password item `mcp-<name>`:
//   hosted: field `token`, sent as `Authorization: Bearer …` by Hermes
//   self-hosted: the fields named in `secrets`, env vars of the MCP pod only
local netpol = import 'helpers/netpol.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'mcp';
local hermesNamespace = 'hermes';

local servers = {
  github: { url: 'https://api.githubcopilot.com/mcp/', fqdn: 'api.githubcopilot.com', token: true },
  linear: { url: 'https://mcp.linear.app/mcp', fqdn: 'mcp.linear.app', token: true },

  // Read-only. Fields: url (the Grafana Cloud stack), token (Viewer service account)
  grafana: {
    image: 'grafana/mcp-grafana:latest',
    port: 8000,
    args: [
      '-t',
      'streamable-http',
      '--address',
      '0.0.0.0:8000',
      // Host header check, port included
      '--allowed-hosts',
      'grafana.mcp:8000,grafana.mcp.svc:8000',
      // '--disable-write',
    ],
    secrets: { GRAFANA_URL: 'url', GRAFANA_SERVICE_ACCOUNT_TOKEN: 'token' },
    egress: { fqdns: [{ pattern: '*.grafana.net' }] },
  },

  // Single-arch image. Serves every caller with its own token, so only Hermes
  // may reach it (see ingress below). Field: token (Forgejo bot user)
  forgejo: {
    image: 'git.b4mad.industries/agentic-forges/forgejo-mcp:latest',
    port: 8080,
    arch: 'amd64',
    args: [
      '--transport',
      'http',
      '--http-port',
      '8080',
      '--host',
      '0.0.0.0',
      '--allowed-hosts',
      'forgejo.mcp,forgejo.mcp.svc',
      '--url',
      'https://git.vpn.dzerv.art',
      '--allow-operator-token-fallback',
    ],
    secrets: { FORGEJO_ACCESS_TOKEN: 'token' },
    egress: { dnsNames: ['**.cluster.local', 'git.vpn.dzerv.art'], endpoints: [netpol.traefikVpn] },
  },
};

local isHosted(s) = std.objectHas(s, 'url');
local tokenEnv(name) = 'MCP_%s_TOKEN' % std.asciiUpper(name);

// A self-hosted server: Deployment + Service, egress default-deny plus its
// own allowances, ingress only from Hermes
local pod(name, s) = {
  server:
    lab.new(name, s.image)
    + lab.withNamespace(namespace)
    + lab.withPort({ port: s.port, name: 'mcp' })
    + (if std.objectHas(s, 'args') then lab.withArgs(s.args) else {})
    + (if std.objectHas(s, 'env') then lab.withEnv(s.env) else {})
    + (if std.objectHas(s, 'secrets') then
         lab.withExternalSecretEnvs(name + '-op', s.secrets, { store: '1password', remoteKey: 'mcp-' + name })
       else {})
    + { workload+: { spec+: { template+: { spec+: {
      automountServiceAccountToken: false,
      securityContext+: { seccompProfile: { type: 'RuntimeDefault' } },
    } + (if std.objectHas(s, 'arch') then { nodeSelector: { 'kubernetes.io/arch': s.arch } } else {}) } } } },

  egress: netpol.egress(name + '-egress', namespace, { 'app.kubernetes.io/name': name }, std.get(s, 'egress', {})),
  ingress: netpol.onlyFromNamespaces(name + '-ingress', namespace, { 'app.kubernetes.io/name': name }, [hermesNamespace]),
};

{
  // The mcp namespace and every self-hosted server
  resources: {
    namespace:
      k.core.v1.namespace.new(namespace)
      + k.core.v1.namespace.metadata.withLabels({
        'pod-security.kubernetes.io/enforce': 'restricted',
        'pod-security.kubernetes.io/enforce-version': 'latest',
      }),
  } + {
    [name]: pod(name, servers[name])
    for name in std.objectFields(servers)
    if !isHosted(servers[name])
  },

  // Hermes' mcp_servers config, for the managed config.yaml
  config:: {
    [name]:
      if isHosted(servers[name]) then
        { url: servers[name].url }
        + (if std.get(servers[name], 'token', false) then { headers: { Authorization: 'Bearer ${%s}' % tokenEnv(name) } } else {})
      else { url: 'http://%s.%s:%d/mcp' % [name, namespace, servers[name].port] }
    for name in std.objectFields(servers)
  },

  // Env vars of the Hermes pod: { ENV: [1password item, field] } for hosted tokens
  tokens:: {
    [tokenEnv(name)]: ['mcp-' + name, 'token']
    for name in std.objectFields(servers)
    if isHosted(servers[name]) && std.get(servers[name], 'token', false)
  },

  // What the Hermes pod's egress policy must allow
  hermesEgress:: {
    fqdns: [{ name: servers[name].fqdn } for name in std.objectFields(servers) if isHosted(servers[name])],
    endpoints: [
      { namespace: namespace, labels: { 'app.kubernetes.io/name': name }, ports: [{ port: servers[name].port }] }
      for name in std.objectFields(servers)
      if !isHosted(servers[name])
    ],
  },
}
