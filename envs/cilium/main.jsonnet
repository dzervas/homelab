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
      // routingMode: 'native',
      // tunnelProtocol: '',
      // devices: 'wg0',
      // MTU: 1392,
      // autoDirectNodeRoutes: true,

      ipam: {
        mode: 'cluster-pool',
        operator: {
          clusterPoolIPv4PodCIDRList: ['10.200.0.0/16'],  // Migration: Ensure this is distinct and unused
        },
      },
      policyEnforcementMode: 'never',  // Migration: Disable policy enforcement
      bpf: {
        hostLegacyRouting: true,  // Migration: Allow for routing between Cilium and the existing overlay
        // masquerade: true,
      },
      socketLB: {
        enabled: true,  // Required for hostPort support
      },
      kubeProxyReplacement: 'true',

      // No reason since everything is on top of wireguard
      // bgpControlPlane: {
      //   enabled: true,
      // },
    },
  }),
}
