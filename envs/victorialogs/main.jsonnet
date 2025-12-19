local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);
local k = import 'k.libsonnet';

local namespace = 'victorialogs';
local vlsingleLabels = {
  'app.kubernetes.io/name': 'vlsingle',
  'app.kubernetes.io/instance': 'victorialogs',
};

{
  // Namespace
  namespace: k.core.v1.namespace.new(namespace),

  // VictoriaLogs single instance (storage)
  vlsingle: helm.template('vlsingle', '../../charts/victoria-logs-single', {
    namespace: namespace,
    values: {
      nameOverride: 'victorialogs',
      server: {
        retentionPeriod: '3',  // Months
        persistentVolume: { size: '20Gi' },
        nodeSelector: { provider: 'oracle' },
      },
      dashboards: {
        enabled: true,
        labels: { grafana_dashboard: '1' },
      },
    },
  }),

  // VictoriaLogs agent (log collector DaemonSet)
  vlagent: helm.template('vlagent', '../../charts/victoria-logs-collector', {
    namespace: namespace,
    values: {
      nameOverride: 'victorialogs',
      remoteWrite: [
        { url: 'http://vlsingle-victorialogs-server:9428' },
      ],
      tolerations: [{
        key: 'storage-only',
        operator: 'Equal',
        value: 'true',
        effect: 'NoSchedule',
      }],
    },
  }),

  // NetworkPolicy to allow Grafana access
  grafanaAccessNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-victorialogs-grafana')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels(vlsingleLabels)
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: [
        { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'grafana' } } },
        { podSelector: { matchLabels: { 'app.kubernetes.io/name': 'grafana' } } },
      ],
    }]),
}
