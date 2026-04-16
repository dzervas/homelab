local affinity = import 'helpers/affinity.libsonnet';
local lab = import 'labsonnet/main.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local traefik = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

local commonHttpOptions(port, fqdn, name=null, matches=null, prefix='common', middleware=[],) = {
  port: port,
  name: if name != null then name else '%s-%d' % [prefix, port],
  httpRoute: {
    gateway: traefik,
    annotations:
      { 'cert-manager.io/cluster-issuer': 'letsencrypt' }
      + if std.length(middleware) > 0 then {
        'traefik.ingress.kubernetes.io/router.middlewares': std.join(', ', [('traefik-%s@kubernetescrd' % m) for m in middleware]),
      } else {},
    [if fqdn != null then 'fqdn']: fqdn,
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

  withPublicHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'http', [])),
  withAnubisHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'anubis', ['anubis'])),
  withMagicEntryHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'magicentry', ['magicentry'])),
  withVpnHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(commonHttpOptions(port, fqdn, name, matches, 'vpn', ['vpnonly'])),

  withOpEnvs(envs, name=null)::
    local secName = if name != null then name else $._name;
    lab.withExternalSecretEnvs(secName + '-op', secName, { storeName: '1password' }),

  // TODO: this is not done
  withRandomEnv(env, name=null)::
    local secName = if name != null then name else $._name;
    externalSecret.new(secName + '-op')
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
