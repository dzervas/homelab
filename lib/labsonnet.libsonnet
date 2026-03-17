local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local lab = import 'labsonnet/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local traefik = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

local publicHttpOptions(port, fqdn, name=null, matches=null) = {
  port: port,
  name: if name != null then name else port,
  httpRoute: {
    gateway: traefik,
    annotations: { 'cert-manager.io/cluster-issuer': 'letsencrypt' },
    [if fqdn != null then 'fqdn']: fqdn,
  } + (if matches != null then { matches: matches } else {}),
};

lab {
  withPublicHttp(port, fqdn, name=null, matches=null)::
    lab.withPort(publicHttpOptions(port, fqdn, name, matches)),

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
}
