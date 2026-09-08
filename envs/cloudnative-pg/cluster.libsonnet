local cnpg = import 'cloudnative-pg-libsonnet/1.27.0/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';

local cluster = cnpg.postgresql.v1.cluster;

{
  new(name, namespace, size, instances=2)::
    cluster.new(name)
    + cluster.metadata.withNamespace(namespace)
    + cluster.spec.withInstances(instances)
    + cluster.spec.storage.withSize(size)
    + cluster.spec.bootstrap.initdb.withDatabase(name)
    + cluster.spec.bootstrap.initdb.withOwner(name)
    + cluster.spec.bootstrap.initdb.withDataChecksums(true)
    + cluster.spec.monitoring.withEnablePodMonitor(true)
    // The operator generates the PodMonitor, so it can't go through
    // metrics-filter.libsonnet. Keep only the cnpg_* metrics; the rest is Go runtime.
    + cluster.spec.monitoring.withPodMonitorMetricRelabelings([
      { sourceLabels: ['__name__'], regex: 'up|scrape_samples_scraped|cnpg_.*', action: 'keep' },
    ])
    + {
      spec+: {
        // Keep database instances off the flaky homelab nodes. CNPG enables
        // cross-node pod anti-affinity by default.
        affinity+: affinity.avoidHomelab,
      },
    },
}
