local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'plane';
local domain = 'projects.dzerv.art';

{
  namespace: k.core.v1.namespace.new(namespace),
  plane: helm.template('plane', '../charts/plane-ce', {
    namespace: namespace,
    values: {
      planeVersion: 'stable',
      ingress: {
        enabled: true,
        ingressClass: 'nginx',
        ingress_annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt',
          'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
          'nginx.ingress.kubernetes.io/auth-tls-verify-client': 'on',
          'nginx.ingress.kubernetes.io/auth-tls-secret': '%s/client-ca' % namespace,
          'nginx.ingress.kubernetes.io/auth-tls-verify-depth': '1',
          'nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream': 'true',
          'nginx.ingress.kubernetes.io/proxy-body-size': '5m',
        },

        appHost: domain,
      },
      ssl: {
        tls_secret_name: 'projects-dzerv-art-cert',
      },
      env: {
        storageClass: 'openebs-replicated',
      },
    },
  }),
}
