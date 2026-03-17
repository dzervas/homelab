local affinity = import 'helpers/affinity.libsonnet';
local lab = import 'labsonnet/main.libsonnet';

local traefik = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

local publicHttpOptions(port, fqdn, name=null, matches=null) = {
  port: port,
  name: if name != null then name else std.toString(port),
  httpRoute: {
    gateway: traefik,
    annotations: { 'cert-manager.io/cluster-issuer': 'letsencrypt' },
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
    lab.withPort(publicHttpOptions(port, fqdn, if name != null then name else 'http-%d' % port, matches)),

  withVpnHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(
      publicHttpOptions(port, fqdn, name, matches) + {
        name: if name != null then name else 'vpn-%d' % port,
        annotations+: { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-vpnonly@kubernetescrd' },
      }
    ),

  withOpEnvs(envs, name=null)::
    local secName = if name != null then name else $._name;
    lab.withExternalSecretEnvs(secName + '-op', secName, { storeName: '1password' }),

  withAffinityPreferHomelab()::
    lab.withAffinity(affinity.preferHomelab),
  withAffinityAvoidHomelab()::
    lab.withAffinity(affinity.avoidHomelab),
}
