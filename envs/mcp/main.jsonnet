// Shared MCP servers for pods labeled mcp/enable: 'true'. To add one, add an entry to `servers`:
// Self-hosted servers are also exposed at https://mcp.vpn.dzerv.art/<name> via the VPN gateway
//
//   Hosted (someone else runs it):
//     name: { url: 'https://…/mcp', fqdn: 'host', token: true }   token: send a bearer token
//   Self-hosted (a pod in the mcp namespace, speaking streamable HTTP on /mcp):
//     name: { image: '…:latest', port: 8080, args: [], env: {}, secrets: { ENV: 'field' },
//             egress: netpol.egress opts, arch: 'amd64', app: lab overrides, token: true }
//
// Tokens and secrets come from the 1Password item `mcp-<name>`:
//   token: true: field `token`, sent as `Authorization: Bearer …` by the client
//   self-hosted: the fields named in `secrets`, env vars of the MCP pod
local gatewayApi = import 'gateway-api.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local networkPolicy = k.networking.v1.networkPolicy;
local httpRoute = gatewayApi.gateway.v1.httpRoute;
local rule = httpRoute.spec.rules;

local namespace = 'mcp';
local domain = 'mcp.vpn.dzerv.art';

local servers = {
  // github: { url: 'https://api.githubcopilot.com/mcp/', fqdn: 'api.githubcopilot.com', token: true },
  // linear: { url: 'https://mcp.linear.app/mcp', fqdn: 'mcp.linear.app', token: true },

  // Read-only. Fields: url (the Grafana Cloud stack), token (Viewer service account)
  // grafana: {
  //   image: 'grafana/mcp-grafana:latest',
  //   port: 8000,
  //   args: [
  //     '-t',
  //     'streamable-http',
  //     '--address',
  //     '0.0.0.0:8000',
  //     // Host header check, port included
  //     '--allowed-hosts',
  //     'grafana.mcp:8000,grafana.mcp.svc:8000',
  //     // '--disable-write',
  //   ],
  //   secrets: { GRAFANA_URL: 'url', GRAFANA_SERVICE_ACCOUNT_TOKEN: 'token' },
  //   egress: { fqdns: [{ pattern: '*.grafana.net' }] },
  // },

  // Fields: token (server bearer token), session-token (Kagi subscription)
  vresto: {
    image: 'ghcr.io/dzervas/vresto:latest',
    port: 8000,
    token: true,
    env: {
      TZ: timezone,
      VRESTO_UNAUTHENTICATED: '1',
      VRESTO_PORT: '8000',  // service defaults to exposing the full tcp url
      VRESTO_RESEARCH_TIMEOUT_SECONDS: std.toString(30 * 60),
      VRESTO_RESEARCH_CONCURRENCY: '10',
      VRESTO_RESEARCH_MODEL: 'deepseek-v4-1-flash',
    },
    secrets: { KAGI_SESSION_TOKEN: 'token' },
    // Public pages, redirects and browser subrequests must not reach private networks
    egress: {
      dnsNames: ['*'],
      cidrs: [netpol.internet],
    },
    app:
      lab.withRunAsUser(10001)
      + lab.withType('StatefulSet')
      + lab.withServiceName('vresto')
      + lab.withPV('/data/cache', { name: 'cache', size: '2Gi', storageClassName: 'longhorn-throwaway' })
      + lab.withEmptyDir('/dev/shm')
      + { workload+: { spec+: { template+: { spec+: {
        volumes: [
          if v.name == 'vresto-dev-shm' then v { emptyDir: { medium: 'Memory', sizeLimit: '256Mi' } } else v
          for v in super.volumes
        ],
      } } } } },
  },

  // Single-arch image. All opted-in callers share the server's Forgejo bot token
  // Field: token (Forgejo bot user)
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
      'forgejo.mcp,forgejo.mcp.svc,' + domain,
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
// own allowances, ingress from opted-in client pods and the VPN gateway
local pod(name, s) = {
  server:
    lab.new(name, s.image)
    + lab.withNamespace(namespace)
    + lab.withPort({ port: s.port, name: 'mcp' })
    + lab.withAffinity(affinity.requireProviders(['homelab']))
    + std.get(s, 'app', {})
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
  ingress:
    networkPolicy.new(name + '-ingress')
    + networkPolicy.metadata.withNamespace(namespace)
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': name })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [
        { namespaceSelector: {}, podSelector: { matchLabels: { 'mcp/enable': 'true' } } },
        {
          namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
          podSelector: { matchLabels: { 'app.kubernetes.io/name': 'traefik' } },
        },
      ],
      ports: [{ port: s.port, protocol: 'TCP' }],
    }]),
};

{
  // The mcp namespace and every self-hosted server
  resources: {
    vpnRoute:
      httpRoute.new('mcp-vpn')
      + httpRoute.metadata.withNamespace(namespace)
      + httpRoute.spec.withHostnames([domain])
      + httpRoute.spec.withParentRefs([
        httpRoute.spec.parentRefs.withName('traefik-gateway')
        + httpRoute.spec.parentRefs.withNamespace('traefik')
        + httpRoute.spec.parentRefs.withSectionName('websecure-vpn'),
      ])
      + httpRoute.spec.withRules([
        rule.withMatches([
          rule.matches.path.withType('PathPrefix')
          + rule.matches.path.withValue('/' + name),
        ])
        // MCP clients use /<name>; each backend still receives its native /mcp endpoint
        + rule.withFilters([
          rule.filters.withType('URLRewrite')
          + rule.filters.urlRewrite.path.withType('ReplacePrefixMatch')
          + rule.filters.urlRewrite.path.withReplacePrefixMatch('/mcp'),
        ])
        + rule.withBackendRefs([
          rule.backendRefs.withName(name)
          + rule.backendRefs.withPort(servers[name].port),
        ])
        for name in std.objectFields(servers)
        if !isHosted(servers[name])
      ]),

    namespace:
      k.core.v1.namespace.new(namespace)
      + k.core.v1.namespace.metadata.withLabels({
        forgejoCreds: 'enabled',
        ghcrCreds: 'enabled',
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
      (if isHosted(servers[name]) then
         { url: servers[name].url }
       else { url: 'http://%s.%s:%d/mcp' % [name, namespace, servers[name].port] })
      + (if std.get(servers[name], 'token', false) then { headers: { Authorization: 'Bearer ${%s}' % tokenEnv(name) } } else {})
    for name in std.objectFields(servers)
  },

  // Env vars of client pods: { ENV: [1password item, field] } for bearer tokens
  tokens:: {
    [tokenEnv(name)]: ['mcp-' + name, 'token']
    for name in std.objectFields(servers)
    if std.get(servers[name], 'token', false)
  },

  // What each client pod's egress policy must allow
  clientEgress:: {
    fqdns: [{ name: servers[name].fqdn } for name in std.objectFields(servers) if isHosted(servers[name])],
    endpoints: [
      { namespace: namespace, labels: { 'app.kubernetes.io/name': name }, ports: [{ port: servers[name].port }] }
      for name in std.objectFields(servers)
      if !isHosted(servers[name])
    ],
  },
}
