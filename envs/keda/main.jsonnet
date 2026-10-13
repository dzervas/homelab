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
      // Retain the operator without Actions workload permissions or a cluster-wide scope
      // No remaining repository-defined scalers; authorize future consumers explicitly
      watchNamespace: namespace,
      // Direct polling needs no external metrics API or admission pod
      metricsServer: { enabled: false, registerAPIService: false },
      webhooks: { enabled: false },
    },
  }),

  // Retired Actions scaler endpoints are gone; retain only DNS and API access
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
    ]),
}
