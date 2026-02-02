local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local affinity = import 'helpers/affinity.libsonnet';

local namespace = 'cilium';

{
  namespace: k.core.v1.namespace.new(namespace),

  cilium: helm.template('cilium', '../../charts/cilium', {
    namespace: namespace,
    values: {
      routingMode: 'native',
      tunnelProtocol: '',
      // devices: ['wg0'],
      MTU: 1392,
      autoDirectNodeRoutes: true,  // Let cilium handle pod routes in nodes

      ipv4NativeRoutingCIDR: '10.200.0.0/16',

      ipam: {
        mode: 'cluster-pool',
        operator: {
          clusterPoolIPv4PodCIDRList: ['10.200.0.0/16'],
        },
      },
      bpf: {
        hostLegacyRouting: false,
        lbExternalClusterIP: true,
        masquerade: true,
      },
      extraConfig: {
        'enable-host-reachable-services': 'true',
      },
      nodePort: { enabled: true },
      socketLB: { enabled: true },
      kubeProxyReplacement: 'true',

      // Direct API server access - avoids chicken-and-egg with kube-proxy disabled
      // TODO: If gr0 is down the cluster might get stuck during a cold start
      k8sServiceHost: '10.20.30.100',
      k8sServicePort: '6443',

      // hubble: { tls: { auto: {
      //   method: 'certmanager',
      //   certManagerIssuerRef: {
      //     name: 'selfsigned',
      //     kind: 'ClusterIssuer',
      //     group: 'cert-manager.io',
      //   },
      // } } },
      // clustermesh: { apiserver: { tls: { auto: {
      //   method: 'certmanager',
      //   certManagerIssuerRef: {
      //     name: 'selfsigned',
      //     kind: 'ClusterIssuer',
      //     group: 'cert-manager.io',
      //   },
      // } } } },

      // No reason since everything is on top of wireguard
      // bgpControlPlane: {
      //   enabled: true,
      // },
    },
  }),
}
