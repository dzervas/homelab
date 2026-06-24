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
        defaultClass: true,
        reclaimPolicy: 'Retain',
        defaultClassReplicaCount: 2,
        defaultDataLocality: 'best-effort',
        // Maybe disable on weak nodes? https://longhorn.io/docs/1.11.0/v2-data-engine/features/selective-v2-data-engine-activation/
        dataEngine: 'v2',

        // V1-only setting; must use the data-engine JSON form or Longhorn rejects it.
        // Keep the counter ON for v1 volumes so auto-salvage can pick the best replica.
        disableRevisionCounter: '{"v1":"false"}',
      },
      longhornUI: { replicas: 1 },
      ingress: ingress.hostString('storage.vpn.dzerv.art'),

      defaultSettings: {
        // v2DataEngine: true,
        defaultDataPath: '/dev/mapper/mainpool-longhorn',
        defaultDataLocality: 'best-effort',
        // Maybe interrupt mode at some point (needs iommu): https://longhorn.io/docs/1.11.0/v2-data-engine/features/interrupt-mode/

        // Disabled: on this cluster's flaky nodes it auto-attaches detached degraded
        // volumes to rebuild, causing attach/detach flapping during recovery
        // (see INCIDENT-2026-06-23-v2-stuck-detach-reactor-churn.md).
        offlineReplicaRebuilding: false,
        // Disabled: rebuild churn amplifier on flaky nodes / v2 — repeatedly implicated
        // as making incidents worse (see both INCIDENT-2026-06-2x reports). 'true' is
        // also an invalid value; valid options are disabled/least-effort/best-effort.
        replicaAutoBalance: 'disabled',

        orphanResourceAutoDeletion: 'replica-data;instance',
        orphanResourceAutoDeletionGracePeriod: 3 * 24 * 60 * 60,
      },

      metrics: { serviceMonitor: { enabled: true } },
    },
  }),
}
