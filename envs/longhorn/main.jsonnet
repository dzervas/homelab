local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local helm = tk.helm.new(std.thisFile);

{
  namespace: k.core.v1.namespace.new('longhorn-system'),

  longhorn: helm.template('longhorn', '../../charts/longhorn', {
    namespace: $.namespace.metadata.name,
    values: {
      networkPolicies: {
        enabled: true,
        type: 'rke2',
      },

      persistence: {
        defaultClass: false,
        reclaimPolicy: 'Retain',
        defaultClassReplicaCount: 2,
        defaultDataLocality: 'best-effort',
        // Maybe disable on weak nodes? https://longhorn.io/docs/1.11.0/v2-data-engine/features/selective-v2-data-engine-activation/
        dataEngine: 'v2',
      },
      longhornUI: { replicas: 1 },
      ingress: ingress.hostString('storage.vpn.dzerv.art'),

      defaultSettings: {
        // v2DataEngine: true,
        defaultDataPath: '/dev/mapper/mainpool-longhorn',
        defaultDataLocality: 'best-effort',
        // Maybe interrupt mode at some point (needs iommu): https://longhorn.io/docs/1.11.0/v2-data-engine/features/interrupt-mode/
      },

      // metrics: { serviceMonitor: { enabled: true } },
    },
  }),
}
