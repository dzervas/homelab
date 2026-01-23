local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local helm = tk.helm.new(std.thisFile);
local k = import 'k.libsonnet';
local networkPolicy = k.networking.v1.networkPolicy;

// local certificate = certManager.nogroup.v1.certificate;

local namespace = 'linstor';
local domain = 'storage.dzerv.art';
local nodeSelector = {
  'linstor/enable': 'true',
};

// Affinity for controller components to avoid homelab provider nodes since they're flaky
local controllerAffinity = {
  nodeAffinity: {
    requiredDuringSchedulingIgnoredDuringExecution: {
      nodeSelectorTerms: [{
        matchExpressions: [{
          key: 'provider',
          operator: 'NotIn',
          values: ['homelab'],
        }],
      }],
    },
  },
};

{
  namespace: k.core.v1.namespace.new(namespace),

  operator: helm.template('piraeus', '../../charts/piraeus', {
    namespace: namespace,
    values: {
      installCRDs: true,
      operator: {
        options: { zapDevel: false },
      },
      tls: {
        certManagerIssuerRef: {
          name: 'selfsigned',
          kind: 'ClusterIssuer',
        },
      },
      tolerations: [],
      affinity: controllerAffinity,
    },
  }),

  cluster: helm.template('linstor-cluster', '../../charts/linstor-cluster', {
    values: {
      linstorCluster: {
        nodeSelector: nodeSelector,
        nfsServer: {
          enabled: false,
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
              affinity: controllerAffinity,
            },
          },
        },

        csiController: {
          podTemplate: {
            spec: {
              tolerations: [],
              affinity: controllerAffinity,
            },
          },
        },

        affinityController: {
          podTemplate: {
            spec: {
              tolerations: [],
              affinity: controllerAffinity,
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

  // The csi-node pods run in host network and they need to be able to reach the controller pod
  // Host networking pods means that they have an IP from a non-k8s CIDR, hence the 0/0 CIDR
  linstorHostNetworkPolicy:
    networkPolicy.new('allow-hostnetwork-controller-access')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/component': 'linstor-controller' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [{ ipBlock: { cidr: '0.0.0.0/0' } }],
      ports: [{ port: 3370, endPort: 3371, protocol: 'TCP' }],
    }]),

  // This is absolutely needed
  operatorWebhookNetworkPolicy:
    k.networking.v1.networkPolicy.new('piraeus-webhook')
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/name': 'piraeus-datastore',
      'app.kubernetes.io/component': 'piraeus-operator',
      'app.kubernetes.io/instance': 'piraeus',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [{ protocol: 'TCP', port: 9443 }],  // The pod listens on 9443 but the service exposes 443!
      },
    ]),

  // Unsure if this is required - is only the controller speaking to the satellites?
  satelliteNetworkPolicy:
    k.networking.v1.networkPolicy.new('linstor-satellite')
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/component': 'linstor-satellite',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { namespaceSelector: {} },
          { podSelector: {} },
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [
          { protocol: 'TCP', port: 3367 },  // satellite
          { protocol: 'TCP', port: 9942 },  // drbd-reactor
        ],
      },
    ]),
}
