local sslOnlyAnnotations = {
  'cert-manager.io/cluster-issuer': 'letsencrypt',
  'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
};

local common(domain) = {
  enabled: true,
  annotations: sslOnlyAnnotations,
  tls: [{
    hosts: [domain],
    secretName: '%s-cert' % std.strReplace(domain, '.', '-'),
  }],
};

local className = 'nginx';

{
  sslOnlyAnnotations: sslOnlyAnnotations,
  mtlsAnnotations(namespace): {
    'nginx.ingress.kubernetes.io/auth-tls-verify-client': 'on',
    'nginx.ingress.kubernetes.io/auth-tls-secret': '%s/client-ca' % namespace,
    'nginx.ingress.kubernetes.io/auth-tls-verify-depth': '1',
    'nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream': 'true',
  } + sslOnlyAnnotations,
  oidcAnnotations(svcName): {
    'magicentry.rs/name': svcName,
    'magicentry.rs/realms': svcName,
    'magicentry.rs/auth-url': 'true',

    'nginx.ingress.kubernetes.io/auth-url': 'http://magicentry.auth.svc.cluster.local:8080/auth-url/status',
    'nginx.ingress.kubernetes.io/auth-signin': 'https://auth.dzerv.art/login',
    'nginx.ingress.kubernetes.io/auth-cache-duration': '200 202 10m',
    'nginx.ingress.kubernetes.io/auth-cache-key': '$remote_user$http_authorization$http_cookie',
  } + sslOnlyAnnotations,

  hostString(domain, annotations={}): common(domain) {
    ingressClassName: className,
    host: domain,
    annotations: annotations,
  },
  hostList(domain, annotations={}): common(domain) {
    ingressClassName: className,
    hosts: [domain],
    annotations: annotations,
  },
  hostObj(domain, annotations={}): common(domain) {
    className: className,
    annotations: annotations,
    hosts: [{
      host: domain,
      paths: [{
        path: '/',
        pathType: 'ImplementationSpecific',
      }],
    }],
  },
  hostObjSingle(domain, annotations={}): common(domain) {
    className: className,
    annotations: annotations,
    host: {
      name: domain,
      path: '/',
      pathType: 'ImplementationSpecific',
    },
  },
}
