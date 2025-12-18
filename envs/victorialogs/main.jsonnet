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
  vlsingle: {
    apiVersion: 'operator.victoriametrics.com/v1',
    kind: 'VLSingle',
    metadata: {
      name: 'victorialogs',
      namespace: namespace,
      labels: vlsingleLabels,
    },
    spec: {
      retentionPeriod: '90d',
      storage: {
        resources: {
          requests: { storage: '20Gi' },
        },
      },
      nodeSelector: { provider: 'oracle' },
    },
  },

  // VictoriaLogs agent (log collector DaemonSet)
  vlagent: {
    apiVersion: 'operator.victoriametrics.com/v1',
    kind: 'VLAgent',
    metadata: {
      name: 'victorialogs-collector',
      namespace: namespace,
    },
    spec: {
      k8sCollector: { enabled: true },
      remoteWrite: [
        { url: 'http://vlsingle-victorialogs:9428/insert/jsonline' },
      ],
    },
  },

  // Grafana datasource ConfigMap (sidecar picks by label grafana_datasource=1)
  grafanaDatasource:
    k.core.v1.configMap.new('victorialogs-grafana-ds')
    + k.core.v1.configMap.metadata.withNamespace(namespace)
    + k.core.v1.configMap.metadata.withLabels({ grafana_datasource: '1' })
    + k.core.v1.configMap.withData({
      'datasource.yaml': std.manifestYamlDoc({
        apiVersion: 1,
        datasources: [
          {
            name: 'VictoriaLogs',
            type: 'victoriametrics-logs-datasource',
            url: std.format('http://vlsingle-victorialogs.%s.svc:9428', namespace),
            isDefault: false,
          },
        ],
      }),
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
      ],
    }]),
}
