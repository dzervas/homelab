local lab = import 'labsonnet/main.libsonnet';

local traefik = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

lab {
  withPublicHttp(port, name=null, matches=null, fqdn=null)::
    lab.withPort({
      port: port,
      name: if name != null then name else 'http-%d' % port,
      httpRoute: {
        gateway: traefik,
        annotations: { 'cert-manager.io/cluster-issuer': 'letsencrypt' },
        [if fqdn != null then 'fqdn']: fqdn,
      } + (if matches != null then { matches: matches } else {}),
    }),

  withVpnHttp(port, name=null, matches=null, fqdn=null)::
    lab.withPort({
      port: port,
      name: if name != null then name else 'vpn-http-%d' % port,
      httpRoute: {
        gateway: traefik,
        annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt',
          'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-vpnonly@kubernetescrd',
        },
        [if fqdn != null then 'fqdn']: fqdn,
      } + (if matches != null then { matches: matches } else {}),
    }),
}
