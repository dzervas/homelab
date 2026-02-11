local gatewayApi = import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local httpRoute = gatewayApi.v1.httpRoute;

{
  // Self-signed certificate for the Gateway HTTPS listener
  gatewayCert: {
    apiVersion: 'cert-manager.io/v1',
    kind: 'Certificate',
    metadata: {
      name: 'gateway-cert',
    },
    spec: {
      secretName: 'gateway-tls',
      issuerRef: {
        name: 'letsencrypt',
        kind: 'ClusterIssuer',
      },
      dnsNames: ['*.dzerv.art', 'dzerv.art'],
      // dnsNames: ['dzerv.art'],
    },
  },

  // Empty Gateway - no routes attached, just listens on 80/443
  // NOTE: Needs k apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml
  gateway: {
    apiVersion: 'gateway.networking.k8s.io/v1',
    kind: 'Gateway',
    metadata: {
      name: 'cilium-gateway',
    },
    spec: {
      gatewayClassName: 'cilium',
      listeners: [
        {
          name: 'http',
          protocol: 'HTTP',
          port: 80,
          allowedRoutes: {
            namespaces: { from: 'All' },
          },
        },
        {
          name: 'https',
          protocol: 'HTTPS',
          port: 443,
          tls: {
            mode: 'Terminate',
            certificateRefs: [{
              kind: 'Secret',
              name: 'gateway-tls',
            }],
          },
          allowedRoutes: {
            namespaces: { from: 'All' },
          },
        },
      ],
    },
  },

  // CiliumNetworkPolicy to allow webhook egress to kube-apiserver.
  // Standard NetworkPolicy ipBlock CIDR rules don't match Cilium's
  // reserved kube-apiserver identity, so we need an explicit entity allow.
  envoyNetworkPolicy: {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      name: 'envoy-allow',
    },
    spec: {
      endpointSelector: {
        matchLabels: { 'k8s-app': 'cilium-envoy' },
      },
      ingress: [{
        fromEntities: ['world', 'cluster', 'ingress'],
        toPorts: [{ ports: [
          { port: '80', protocol: 'TCP' },
          { port: '443', protocol: 'TCP' },
        ] }],
      }],
    },
  },
}
