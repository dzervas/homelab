local cnpg = import 'cloudnative-pg-libsonnet/1.27.0/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';

local cluster = cnpg.postgresql.v1.cluster;

{
  new(name, namespace, size, instances=2)::
    cluster.new(name)
    + cluster.metadata.withNamespace(namespace)
    + cluster.spec.withInstances(instances)
    + cluster.spec.storage.withSize(size)
    + cluster.spec.storage.withStorageClass('longhorn-stable')
    + cluster.spec.bootstrap.initdb.withDatabase(name)
    + cluster.spec.bootstrap.initdb.withOwner(name)
    + cluster.spec.bootstrap.initdb.withDataChecksums(true)
    + cluster.spec.monitoring.withEnablePodMonitor(true)
    + {
      spec+: {
        // Keep database instances off the flaky homelab nodes. CNPG enables
        // cross-node pod anti-affinity by default.
        affinity+: affinity.avoidHomelab,
      },
    },
}
