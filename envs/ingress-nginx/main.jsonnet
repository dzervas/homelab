local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'ingress';

// Render ingress-nginx Helm chart (v4.12.4 in TF) with equivalent values
{
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'privileged',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    }),

  ingressNginx:
    helm.template('ingress-nginx', '../../charts/ingress-nginx', {
      namespace: namespace,
      values: {
        controller: {
          // TODO: Eliminate this
          allowSnippetAnnotations: true,
          enableAnnotationValidations: true,

          watchIngressWithoutClass: true,
          ingressClassResource: { default: true },

          networkPolicy: { enabled: true },

          kind: 'DaemonSet',
          hostPort: { enabled: true },
          service: { type: 'ClusterIP' },

          // hostNetwork: true
          // dnsPolicy: "ClusterFirstWithHostNet" // Use cluster DNS, even in host network

          // TODO: Add more pages
          config: {
            'custom-http-errors': '503',
            'annotations-risk-level': 'Critical',
          },

          metrics: {
            enabled: true,
            serviceMonitor: { enabled: true },
          },
        },

        defaultBackend: {
          enabled: true,
          image: {
            registry: 'registry.k8s.io',
            image: 'ingress-nginx/custom-error-pages',
            tag: 'v1.2.3',
          },
          extraVolumes: [{
            name: 'custom-error-pages',
            configMap: {
              name: 'custom-error-pages',
              items: [
                { key: '503', path: '503.html' },
              ],
            },
          }],
          extraVolumeMounts: [{
            name: 'custom-error-pages',
            mountPath: '/www',
          }],
        },
      },
    }),

  customErrorPagesConfigMap:
    k.core.v1.configMap.new('custom-error-pages')
    + k.core.v1.configMap.metadata.withNamespace(namespace)
    + k.core.v1.configMap.withData({
      '503': importstr '../k8s/503.html',
    }),
}
