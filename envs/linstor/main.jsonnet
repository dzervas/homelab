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
      // ingress: ingress.hostString(domain, ingress.mtlsAnnotations(namespace)),
      linstorCluster: {
        nodeSelector: nodeSelector,
        nfsServer: {
          enabled: false,
        },
        // apiTLS: {
        //   certManager: {
        //     name: 'selfsigned',
        //     kind: 'ClusterIssuer',
        //   },
        // },
        // internalTLS: {
        //   certManager: {
        //     name: 'selfsigned',
        //     kind: 'ClusterIssuer',
        //   },
        // },
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
        // internalTLS: {
        //   certManager: {
        //     name: 'selfsigned',
        //     kind: 'ClusterIssuer',
        //   },
        // },
        deletionPolicy: 'Evacuate',

        podTemplate: {
          spec: {
            initContainers: [{
              name: 'drbd-module-loader',
              '$patch': 'delete',
            }],
          },
        },
      }],

      linstorNodeConnections: [],

      storageClasses: [{
        name: 'linstor',
        // annotations: {
        //   'storageclass.kubernetes.io/is-default-class': 'true',
        // },
        provisioner: 'linstor.csi.linbit.com',
        reclaimPolicy: 'Delete',
        allowVolumeExpansion: true,
        volumeBindingMode: 'WaitForFirstConsumer',
        podTemplate: {
          spec: {
            hostNetwork: true,
          },
        },
        parameters: {
          'linstor.csi.linbit.com/autoPlace': '2',
          'linstor.csi.linbit.com/storagePool': 'lvm-thin',
          // This can (and probably should) be a complex rule-based placement strategy - https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#s-kubernetes-params-allow-remote-volume-access
          'linstor.csi.linbit.com/allowRemoteVolumeAccess': 'false',
        },
      }],

      volumeSnapshotClasses: [{
        name: 'linstor-snapshot',
        // annotations: {
        //   'storageclass.kubernetes.io/is-default-class': 'true',
        // },
        driver: 'linstor.csi.linbit.com',
        deletionPolicy: 'Retain',
      }],

      // TODO: Make sure this works
      monitoring: {
        enabled: true,
      },
    },
  }),
}
