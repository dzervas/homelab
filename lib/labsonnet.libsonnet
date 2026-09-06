local externalSecrets = import 'external-secrets.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local lab = import 'labsonnet/main.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local traefik(sectionName='websecure') = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: sectionName,
};

local routeNameFor(name, prefix, port) =
  if name != null then name else '%s-%d' % [prefix, port];

local ipFilteringMiddleware(name, cidrs=null) = {
  apiVersion: 'traefik.io/v1alpha1',
  kind: 'Middleware',
  metadata: { name: name },
  spec: {
    ipAllowList: {
      sourceRange: if cidrs != null then cidrs else ['10.50.50.0/24'],
    },
  },
};

local commonHttpOptions(port, fqdn, name=null, matches=null, prefix='common', middleware=[], sectionName='websecure') =
  local routeName = routeNameFor(name, prefix, port);
  {
    port: port,
    name: routeName,
    httpRoute: {
      [if fqdn != null then 'fqdn']: fqdn,

      gateway: traefik(sectionName),
      annotations: { 'cert-manager.io/cluster-issuer': 'letsencrypt' },

      // https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/#using-traefik-middleware-as-httproute-filter
      // TODO: Since a chain is used, there's no reason to map
      filters: std.map(
        function(m) {
          type: 'ExtensionRef',
          extensionRef: {
            group: 'traefik.io',
            kind: 'Middleware',
            name: routeName,
          },
        },
        middleware
      ),
    } + (if matches != null then { matches: matches } else {}),
  };

lab {
  new(name, image, ghcr=false)::
    lab.new(name, image)
    + (if std.startsWith(image, 'ghcr.io/dzervas/') || ghcr then (
         lab.withNamespaceLabels({ ghcrCreds: 'enabled' })
         + lab.withImagePullSecrets(['ghcr-cluster-secret'])
       ) else {})
  ,

  // TODO: This is shitty
  withPublicHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'http', [])),
  withPublicTCP(port, sectionName, name=null)::
    lab.withPort({
      port: port,
      name: if name != null then name else '%s-%d' % ['tcp', port],
      tcpRoute: { gateway: traefik(sectionName) },
    }),

  withVpnHttp(port, fqdn, cidrs=null, name=null)::
    local rn = routeNameFor(name, 'vpn', port);
    lab.withPort(
      commonHttpOptions(port, fqdn, name, null, 'vpn', if cidrs != null then ['ipfilter-' + rn] else [], 'websecure-vpn')
    )
    + if cidrs != null then { ['ipfilter-' + rn]: ipFilteringMiddleware(rn, cidrs) } else {},

  withOpEnvs(envs, name=null)::
    local secName = if name != null then name else $._name;
    lab.withExternalSecretEnvs(secName + '-op', envs, { store: '1password', remoteKey: secName }),

  // TODO: this is not done
  withRandomEnv(env, name=null)::
    local secName = if name != null then name else $._name;
    externalSecret.new(secName + '-gen')
    + externalSecret.spec.secretStoreRef.withKind('ClusterGenerator')
    + externalSecret.spec.secretStoreRef.withName('password')
    + externalSecret.spec.target.template.withData({ [env]: '{{ .password }}' })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }]),

  withAffinityPreferHomelab()::
    lab.withAffinity(affinity.preferHomelab),
  withAffinityAvoidHomelab()::
    lab.withAffinity(affinity.avoidHomelab),
}
