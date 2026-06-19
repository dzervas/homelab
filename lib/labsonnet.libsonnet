local externalSecrets = import 'external-secrets.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local lab = import 'labsonnet/main.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local traefik = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

local routeNameFor(name, prefix, port) =
  if name != null then name else '%s-%d' % [prefix, port];

local localChain(name, middleware) = {
  apiVersion: 'traefik.io/v1alpha1',
  kind: 'Middleware',
  metadata: { name: name },
  spec: {
    chain: {
      middlewares: std.map(
        function(m) { name: m, namespace: 'traefik' },
        middleware,
      ),
    },
  },
};

local commonHttpOptions(port, fqdn, name=null, matches=null, prefix='common', middleware=[]) =
  local routeName = routeNameFor(name, prefix, port);
  {
    port: port,
    name: routeName,
    httpRoute: {
      [if fqdn != null then 'fqdn']: fqdn,

      gateway: traefik,
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
  withAnubisHttp(port, fqdn, name=null, matches=null)::
    local rn = routeNameFor(name, 'anubis', port);
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'anubis', ['anubis']))
    + { ['middleware-' + rn]: localChain(rn, ['anubis']) },
  withMagicEntryHttp(port, fqdn, name=null, matches=null)::
    local rn = routeNameFor(name, 'magicentry', port);
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'magicentry', ['magicentry']))
    + { ['middleware-' + rn]: localChain(rn, ['magicentry']) },
  withVpnHttp(port, fqdn, name=null, matches=null)::
    local rn = routeNameFor(name, 'vpn', port);
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'vpn', ['vpnonly']))
    + { ['middleware-' + rn]: localChain(rn, ['vpnonly']) },
  withPublicTCP(port, sectionName, name=null)::
    lab.withPort({
      port: port,
      name: if name != null then name else '%s-%d' % ['tcp', port],
      tcpRoute: { gateway: traefik { sectionName: sectionName } },
    }),

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
