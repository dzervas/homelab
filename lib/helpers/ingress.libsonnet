local className = 'traefik';

{
  certAnnotations:: { 'cert-manager.io/cluster-issuer': 'letsencrypt' },
  authAnnotation(auth='mtls')::
    if auth == 'vpn' then
      { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-vpnonly@kubernetescrd' }
    else if auth == 'magicentry' then
      { 'traefik.ingress.kubernetes.io/router.middlewares': 'traefik-magicentry@kubernetescrd' }
    else if auth == 'mtls' then
      { 'traefik.ingress.kubernetes.io/router.tls.options': 'traefik-mtls@kubernetescrd' }
    else if auth == 'public' then
      {}
    else
      error 'Unsupported auth type for ingress',


  common(domain):: {
    enabled: true,
    annotations:
      $.certAnnotations +
      if std.endsWith(domain, '.vpn.dzerv.art') || std.endsWith(domain, '.ts.dzerv.art')
      then $.authAnnotation('vpn') else {},
    tls: [{
      hosts: [domain],
      secretName: '%s-cert' % std.strReplace(domain, '.', '-'),
    }],
  },

  vpnAnnotations(namespace):: $.certAnnotations + $.authAnnotation('vpn'),
  mtlsAnnotations(namespace):: $.certAnnotations + $.authAnnotation('mtls'),
  magicentryAnnotations(name, realms):: $.certAnnotations + $.authAnnotation('magicentry') + {
    'magicentry.rs/name': name,
    'magicentry.rs/realms': realms,
    'magicentry.rs/auth-url': 'true',
  },

  hostString(domain, annotations={}):: $.common(domain) {
    ingressClassName: className,
    host: domain,
    annotations+: annotations,
  },
  hostList(domain, annotations={}):: $.common(domain) {
    ingressClassName: className,
    hosts: [domain],
    annotations+: annotations,
  },
  hostObj(domain, annotations={}):: $.common(domain) {
    ingressClassName: className,
    annotations+: annotations,
    hosts: [{
      host: domain,
      paths: [{
        path: '/',
        pathType: 'ImplementationSpecific',
      }],
    }],
  },
  hostObjSingle(domain, annotations={}):: $.common(domain) {
    className: className,
    annotations+: annotations,
    host: {
      name: domain,
      path: '/',
      pathType: 'ImplementationSpecific',
    },
  },
}
