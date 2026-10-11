local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';

local ciliumNetworkPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local helm = tk.helm.new(std.thisFile);

local namespace = 'keda';

{
  namespace: k.core.v1.namespace.new(namespace),

  keda: helm.template('keda', '../../charts/keda', {
    namespace: namespace,
    // Scoped RoleBindings share a name across namespaces
    nameFormat: '{{ print .kind "_" .metadata.namespace "_" .metadata.name | snakecase }}',
    values: {
      // The chart binds workload permissions only in the watched and operator namespaces
      watchNamespace: 'forgejo-runners',
      // ScaledJobs poll directly in the operator; no external metrics API or admission pod needed
      metricsServer: { enabled: false, registerAPIService: false },
      webhooks: { enabled: false },
    },
  }),

  // The chart's Cilium policy allows the entire cluster; only these scaler destinations are needed
  operatorEgress:
    ciliumNetworkPolicy.new('keda-operator-egress')
    + ciliumNetworkPolicy.metadata.withNamespace(namespace)
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({
      'app.kubernetes.io/name': 'keda-operator',
    })
    + ciliumNetworkPolicy.spec.withEgress([
      ciliumNetworkPolicy.spec.egress.withToEndpoints([{
        matchLabels: {
          'k8s:io.kubernetes.pod.namespace': 'kube-system',
          'k8s:k8s-app': 'kube-dns',
        },
      }])
      + ciliumNetworkPolicy.spec.egress.withToPorts([{
        ports: [{ port: '53', protocol: 'UDP' }, { port: '53', protocol: 'TCP' }],
      }]),
      ciliumNetworkPolicy.spec.egress.withToEntities(['kube-apiserver']),
      ciliumNetworkPolicy.spec.egress.withToEndpoints([{
        matchLabels: {
          'k8s:io.kubernetes.pod.namespace': 'forgejo',
          'k8s:app.kubernetes.io/name': 'forgejo',
        },
      }])
      + ciliumNetworkPolicy.spec.egress.withToPorts([{
        ports: [{ port: '80', protocol: 'TCP' }],
      }]),
    ]),
}
