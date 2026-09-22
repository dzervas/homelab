local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local affinity = import 'helpers/affinity.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';

local gateway = import './gateway.libsonnet';

{
  cilium: helm.template('cilium', '../../charts/cilium', {
    namespace: 'kube-system',
    values: {
      rollOutCiliumPods: true,
      hubble: {
        relay: { enabled: true },
        ui: {
          enabled: true,
          ingress: ingress.hostList('network.vpn.dzerv.art', ingress.magicentryAnnotations('Cilium Hubble', 'admin')),
          service: {
            labels: { 'magicentry.rs/enable': 'true' },
            annotations: {
              'magicentry.rs/name': 'Cilium Hubble',
              'magicentry.rs/url': 'https://network.vpn.dzerv.art',
              'magicentry.rs/realms': 'admin',
              'magicentry.rs/auth_url_origins': 'https://network.vpn.dzerv.art',
            },
          },
        },
      },

      // No encapsulation mode:
      // routingMode: 'native',
      // tunnelProtocol: '',
      // devices: ['wg0'],
      // MTU: 1392,
      // autoDirectNodeRoutes: true,  // Let cilium handle pod routes in nodes
      // Probably also needs IPAM kubernetes and custom podCIDR per node and wireguard acceptips
      // Cilium auto-detects MTU correctly

      ipv4NativeRoutingCIDR: '10.200.0.0/16',

      ipam: {
        mode: 'cluster-pool',
        operator: {
          clusterPoolIPv4PodCIDRList: ['10.200.0.0/16'],
        },
      },
      bpf: {
        hostLegacyRouting: false,
        // TODO: Disable after moving to gateway api
        // hostLegacyRouting: true,
        lbExternalClusterIP: true,
        masquerade: true,
      },
      extraConfig: {
        'enable-host-reachable-services': 'true',
      },
      socketLB: { enabled: true, hostNamespaceOnly: true },
      kubeProxyReplacement: 'true',

      // RKE2 exposes its built-in API client load balancer on agents at this
      // address; server nodes expose their local API server at the same address.
      k8sServiceHost: '127.0.0.1',
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
  // } + gateway
}
