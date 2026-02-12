local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'traefik';

local middleware = import './middleware.libsonnet';

{
  namespace: k.core.v1.namespace.new(namespace),

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

  traefik:
    helm.template('traefik', '../../charts/traefik', {
      namespace: namespace,
      values: {
        deployment: { kind: 'DaemonSet' },
        service: { type: 'ClusterIP' },
        updateStrategy: {
          // Required due to hostNetwork
          rollingUpdate: {
            maxUnavailable: 2,
            maxSurge: null,
          },
        },

        api: { dashboard: false },
        logs: {
          access: { enabled: true },
        },
        global: {
          checkNewVersion: false,
          sendAnonymousUsage: false,
        },

        ingressClass: {
          enabled: true,
          isDefaultClass: false,
        },
        gateway: {
          listeners: {
            web: { namespacePolicy: { from: 'All' } },
            websecure: {
              port: 8443,
              protocol: 'HTTPS',
              namespacePolicy: { from: 'All' },
              certificateRefs: [{
                name: 'gateway-tls',
                kind: 'Secret',
              }],
            },
          },
        },
        providers: {
          kubernetesCRD: { enabled: true },
          kubernetesIngress: { enabled: true },
          kubernetesGateway: { enabled: true },
        },
        // TODO: Enable this
        // ocsp: { enabled: true },

        ports: {
          web: { hostPort: 80 },
          websecure: { hostPort: 443 },
        },
      },
    }),

  traefikNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-traefik')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'traefik' })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: [{
        // For some reason VPN CIDR doesn't work
        ipBlock: {
          cidr: '0.0.0.0/0',
        },
      }],
      ports: [{
        port: 80,
        protocol: 'TCP',
      }, {
        port: 443,
        protocol: 'TCP',
      }],
    }]),
} + middleware
