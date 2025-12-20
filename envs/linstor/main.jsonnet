local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local helm = tk.helm.new(std.thisFile);
local k = import 'k.libsonnet';

// local certificate = certManager.nogroup.v1.certificate;

local namespace = 'linstor';
local domain = 'storage.dzerv.art';
local nodeSelector = {
  'linstor/enable': 'true',
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
            // hostNetwork: true,
            initContainers: [{
              name: 'drbd-module-loader',
              '$patch': 'delete',
            }],
          },
        },
      }],

      linstorNodeConnections: [
        {
          // asynchronous, protocol A - https://linbit.com/drbd-user-guide/drbd-guide-9_0-en/#s-replication-protocols
          name: 'within-provider',
          selector: [{
            matchLabels: [{ key: 'provider', op: 'Same' }],
          }],
          properties: [
            { name: 'DrbdOptions/Net/protocol', value: 'A' },
          ],
          // paths: [{ name: 'wg', interface: 'wg0' }],
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
          // paths: [{ name: 'wg', interface: 'wg0' }],
        },
      ],

      storageClasses: [{
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
        // podTemplate: {
        //   spec: {
        //     hostNetwork: true,
        //   },
        // },
        parameters: {
          'linstor.csi.linbit.com/autoPlace': '2',
          'linstor.csi.linbit.com/storagePool': 'lvm-thin',
          // This can (and probably should) be a complex rule-based placement strategy - https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#s-kubernetes-params-allow-remote-volume-access
          'linstor.csi.linbit.com/allowRemoteVolumeAccess': 'false',
        },
      }],

      // volumeSnapshotClasses: [{
      //   name: 'linstor',
      //   annotations: {
      //     'snapshot.storage.kubernetes.io/is-default-class': 'true',
      //   },
      //   driver: 'linstor.csi.linbit.com',
      //   deletionPolicy: 'Retain',
      // }],

      // TODO: Make sure this works
      monitoring: {
        enabled: true,
      },
    },
  }),

  // The csi-node pods run in host network and they need to be able to reach the controller pod
  // Host networking pods means that they have an IP from a non-k8s CIDR, hence the 0/0 CIDR
  linstorHostNetworkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-hostnetwork-controller-access',
      namespace: namespace,
    },
    spec: {
      podSelector: {
        matchLabels: {
          'app.kubernetes.io/component': 'linstor-controller',
        },
      },
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            {
              // For some reason VPN CIDR doesn't work
              ipBlock: {
                cidr: '0.0.0.0/0',
              },
            },
          ],
          ports: [
            {
              protocol: 'TCP',
              port: 3370,
              endPort: 3371,
            },
          ],
        },
      ],
    },
  },

  operatorWebhookNetworkPolicy:
    k.networking.v1.networkPolicy.new('piraeus-webhook')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/name': 'piraeus-datastore',
      'app.kubernetes.io/component': 'piraeus-operator',
      'app.kubernetes.io/instance': 'piraeus',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { namespaceSelector: {} },
          { podSelector: {} },
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [{ protocol: 'TCP', port: 443 }],
      },
    ]),

  satelliteNetworkPolicy:
    k.networking.v1.networkPolicy.new('linstor-satellite')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
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
        ports: [{ protocol: 'TCP', port: 443 }],
      },
    ]),

  // These have an exporter that listens on hostnetwork, needing this hack :/
  // works without it?
  // linstorMetricsNetworkPolicy: {
  //   apiVersion: 'networking.k8s.io/v1',
  //   kind: 'NetworkPolicy',
  //   metadata: {
  //     name: 'allow-hostnetwork-satellite-metrics-access',
  //     namespace: namespace,
  //   },
  //   spec: {
  //     podSelector: {
  //       matchLabels: {
  //         'app.kubernetes.io/component': 'linstor-satellite',
  //       },
  //     },
  //     policyTypes: ['Ingress'],
  //     ingress: [
  //       {
  //         from: [
  //           {
  //             // For some reason VPN CIDR doesn't work
  //             ipBlock: {
  //               cidr: '0.0.0.0/0',
  //             },
  //           },
  //         ],
  //         ports: [
  //           {
  //             protocol: 'TCP',
  //             port: 9942,
  //           },
  //         ],
  //       },
  //     ],
  //   },
  // },
}
