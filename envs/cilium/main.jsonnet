local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local affinity = import 'helpers/affinity.libsonnet';
local gatewayApi = import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local httpRoute = gatewayApi.v1.httpRoute;

{
  // Self-signed certificate for the Gateway HTTPS listener
  // gatewayCert: {
  //   apiVersion: 'cert-manager.io/v1',
  //   kind: 'Certificate',
  //   metadata: {
  //     name: 'gateway-cert',
  //   },
  //   spec: {
  //     secretName: 'gateway-tls',
  //     issuerRef: {
  //       name: 'letsencrypt',
  //       kind: 'ClusterIssuer',
  //     },
  //     dnsNames: ['*.dzerv.art', 'dzerv.art'],
  //     // dnsNames: ['dzerv.art'],
  //   },
  // },

  // Empty Gateway - no routes attached, just listens on 80/443
  // NOTE: Needs k apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml
  // gateway: {
  //   apiVersion: 'gateway.networking.k8s.io/v1',
  //   kind: 'Gateway',
  //   metadata: {
  //     name: 'cilium-gateway',
  //   },
  //   spec: {
  //     gatewayClassName: 'cilium',
  //     listeners: [
  //       {
  //         name: 'http',
  //         protocol: 'HTTP',
  //         port: 80,
  //         allowedRoutes: {
  //           namespaces: { from: 'All' },
  //         },
  //       },
  //       {
  //         name: 'https',
  //         protocol: 'HTTPS',
  //         port: 443,
  //         tls: {
  //           mode: 'Terminate',
  //           certificateRefs: [{
  //             kind: 'Secret',
  //             name: 'gateway-tls',
  //           }],
  //         },
  //         allowedRoutes: {
  //           namespaces: { from: 'All' },
  //         },
  //       },
  //     ],
  //   },
  // },

  cilium: helm.template('cilium', '../../charts/cilium', {
    namespace: 'kube-system',
    values: {
      rollOutCiliumPods: true,
      hubble: {
        relay: { enabled: true },
        ui: { enabled: true },
      },

      // No encapsulation mode:
      // routingMode: 'native',
      // tunnelProtocol: '',
      // devices: ['wg0'],
      // MTU: 1392,
      // autoDirectNodeRoutes: true,  // Let cilium handle pod routes in nodes
      // Probably also needs IPAM kubernetes and custom podCIDR per node and wireguard acceptips

      ipv4NativeRoutingCIDR: '10.200.0.0/16',

      ipam: {
        mode: 'cluster-pool',
        operator: {
          clusterPoolIPv4PodCIDRList: ['10.200.0.0/16'],
        },
      },
      bpf: {
        // hostLegacyRouting: false,
        // TODO: Disable after moving to gateway api
        hostLegacyRouting: true,
        lbExternalClusterIP: true,
        masquerade: true,
      },
      extraConfig: {
        'enable-host-reachable-services': 'true',
      },
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

      // envoy: {
      //   securityContext: {
      //     capabilities: {
      //       envoy: [
      //         // Needed by envoy, check values.yaml
      //         'NET_ADMIN',
      //         'SYS_ADMIN',
      //         'NET_BIND_SERVICE',
      //       ],
      //       keepCapNetBindService: true,
      //     },
      //   },
      // },
      // envoyConfig: { enabled: true },

      // gatewayAPI: {
      //   enabled: true,
      //   hostNetwork: { enabled: true },
      //   gatewayClass: { create: 'true' },
      // },

      // No reason since everything is on top of wireguard
      // bgpControlPlane: {
      //   enabled: true,
      // },
    },
  }),

  // CiliumNetworkPolicy to allow webhook egress to kube-apiserver.
  // Standard NetworkPolicy ipBlock CIDR rules don't match Cilium's
  // reserved kube-apiserver identity, so we need an explicit entity allow.
  // envoyNetworkPolicy: {
  //   apiVersion: 'cilium.io/v2',
  //   kind: 'CiliumNetworkPolicy',
  //   metadata: {
  //     name: 'envoy-allow',
  //   },
  //   spec: {
  //     endpointSelector: {
  //       matchLabels: { 'k8s-app': 'cilium-envoy' },
  //     },
  //     ingress: [{
  //       fromEntities: ['world', 'cluster', 'ingress'],
  //       toPorts: [{ ports: [
  //         { port: '80', protocol: 'TCP' },
  //         { port: '443', protocol: 'TCP' },
  //       ] }],
  //     }],
  //   },
  // },
}
