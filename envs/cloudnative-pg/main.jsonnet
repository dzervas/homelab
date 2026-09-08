local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local metricsFilter = import 'metrics-filter.libsonnet';
local shared = import './shared.libsonnet';

local namespace = 'cnpg-system';

{
  namespace: k.core.v1.namespace.new(namespace),

  // The operator's PodMonitor is mostly controller-runtime/Go internals.
  cloudnativePg:
    metricsFilter.allowList(helm.template('cloudnative-pg', '../../charts/cloudnative-pg', {
      namespace: namespace,
      values: {
        fullnameOverride: 'cloudnative-pg',
        replicaCount: 2,
        affinity: affinity.avoidHomelab,
        resources: {
          requests: { cpu: '100m', memory: '100Mi' },
          limits: { memory: '256Mi' },
        },
        monitoring: {
          podMonitorEnabled: true,
          grafanaDashboard: { create: true },
        },
      },
    }), 'up|scrape_samples_scraped|cnpg_.*'),
} + shared
