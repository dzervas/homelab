local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);
local affinity = import 'helpers/affinity.libsonnet';

local nodeSelector = { 'linstor/enable': 'true' };

{
  cluster: helm.template('linstor-cluster', '../../charts/linstor-cluster', {
    values: {
      linstorCluster: {
        nodeSelector: nodeSelector,
        nfsServer: {
          enabled: true,
        },

        tolerations: [{
          key: 'storage-only',
          operator: 'Equal',
          value: 'true',
          effect: 'NoSchedule',
        }],

        controller: {
          podTemplate: {
            spec: {
              tolerations: [],
              affinity: affinity.avoidHomelab,
            },
          },
        },

        csiController: {
          podTemplate: {
            spec: {
              tolerations: [],
              affinity: affinity.avoidHomelab,
            },
          },
        },

        affinityController: {
          podTemplate: {
            spec: {
              tolerations: [],
              affinity: affinity.avoidHomelab,
            },
          },
        },
      },
      createApiTLS: 'cert-manager',
      createInternalTLS: 'cert-manager',

      linstorSatelliteConfigurations: [{
        name: 'satellite-config',
        nodeSelector: nodeSelector,
        storagePools: [{
          name: 'lvm-thin',
          lvmThinPool: {
            volumeGroup: 'mainpool',
            thinPool: 'thinpool',
          },
        }],

        properties: [
          // https://kb.linbit.com/drbd-reactor/drbd-reactor-configuring-freeze-feature/#configuring-required-drbd-options
          // { name: 'DrbdOptions/Resource/on-no-quorum', value: 'suspend-io' },
          // { name: 'DrbdOptions/Resource/on-no-data-accessible', value: 'suspend-io' },
          // { name: 'DrbdOptions/Resource/on-suspended-primary', value: 'force-secondary' },
          // { name: 'DrbdOptions/Resource/rr-conflict', value: 'retry-connect' },
        ],
        deletionPolicy: 'Evacuate',

        podTemplate: {
          spec: {
            hostNetwork: true,
            initContainers: [{
              name: 'drbd-module-loader',
              '$patch': 'delete',
            }],
          },
        },
      }],

      linstorNodeConnections: [
        // They pick up the address/iface that they use for kubernetes traffic (wg0 in this case)
        {
          // asynchronous, protocol A - https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#s-replication-protocols
          name: 'within-provider',
          selector: [{
            matchLabels: [{ key: 'provider', op: 'Same' }],
          }],
          properties: [
            { name: 'DrbdOptions/Net/protocol', value: 'A' },
          ],
        },
        {
          // semi-synchronous, protocol B - https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#s-replication-protocols
          name: 'cross-provider',
          selector: [{
            matchLabels: [{ key: 'provider', op: 'NotSame' }],
          }],
          properties: [
            { name: 'DrbdOptions/Net/protocol', value: 'B' },
          ],
        },
      ],

      storageClasses: [
        {
          name: 'linstor',
          annotations: {
            'storageclass.kubernetes.io/is-default-class': 'true',
          },
          provisioner: 'linstor.csi.linbit.com',
          // To patch all pvs to be Retain:
          // k get pv -o json | jq -r '.items[] | select(.spec.storageClassName == "linstor").metadata.name' | xargs -L1 kubectl patch pv -p '{"spec": {"persistentVolumeReclaimPolicy": "Retain"}}'
          reclaimPolicy: 'Retain',
          allowVolumeExpansion: true,
          volumeBindingMode: 'WaitForFirstConsumer',
          parameters: {
            'linstor.csi.linbit.com/autoPlace': '2',
            'linstor.csi.linbit.com/storagePool': 'lvm-thin',
            // This can (and probably should) be a complex rule-based placement strategy - https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#s-kubernetes-params-allow-remote-volume-access
            'linstor.csi.linbit.com/allowRemoteVolumeAccess': std.manifestYamlDoc([{ fromSame: ['provider'] }]),
          },
        },
        {
          name: 'linstor-ha',
          provisioner: 'linstor.csi.linbit.com',
          reclaimPolicy: 'Retain',
          allowVolumeExpansion: true,
          volumeBindingMode: 'WaitForFirstConsumer',
          parameters: {
            'linstor.csi.linbit.com/autoPlace': '3',
            'linstor.csi.linbit.com/storagePool': 'lvm-thin',
            'linstor.csi.linbit.com/allowRemoteVolumeAccess': 'true',
          },
        },
      ],

      // https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#_restoring_from_remote_snapshots
      volumeSnapshotClasses: [{
        name: 'linstor',
        annotations: {
          'snapshot.storage.kubernetes.io/is-default-class': 'true',
        },
        driver: 'linstor.csi.linbit.com',
        deletionPolicy: 'Retain',
        parameters: {
          // TODO: Re-enable s3 as well
          // Needs:  k linstor remote create s3 --use-path-style rclone-s3 rclone-s3.rclone.svc.cluster.local linstor rclone dummy dummy
          // Needs a secret as well
          // 'snap.linstor.csi.linbit.com/type': 'S3',
          // 'snap.linstor.csi.linbit.com/remote-name': 'rclone-s3',
          // 'snap.linstor.csi.linbit.com/allow-incremental': 'true',
          // 'snap.linstor.csi.linbit.com/s3-bucket': 'linstor',
          // 'snap.linstor.csi.linbit.com/s3-endpoint': 'rclone-s3.rclone.svc.cluster.local',
          // 'snap.linstor.csi.linbit.com/s3-use-path-style': 'true',
        },
      }],

      monitoring: {
        enabled: true,
      },
    },
  }),
}
