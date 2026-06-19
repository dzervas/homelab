local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local middleware = import './middleware.libsonnet';
local anubis = import './anubis.libsonnet';

{
  namespace: k.core.v1.namespace.new('traefik'),

  traefik:
    helm.template('traefik', '../../charts/traefik', {
      namespace: $.namespace.metadata.name,
      values: {
        deployment: { kind: 'DaemonSet' },
        service: { spec: { type: 'ClusterIP' } },
        updateStrategy: {
          // Required due to hostNetwork
          rollingUpdate: {
            maxUnavailable: 2,
            maxSurge: null,
          },
        },

        api: { dashboard: false },
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
            ssh: {
              port: 2222,
              protocol: 'TCP',
              namespacePolicy: { from: 'All' },
            },
          },
        },
        providers: {
          kubernetesCRD: {
            enabled: true,
            allowCrossNamespace: true,
          },
          kubernetesIngress: { enabled: true },
          kubernetesGateway: {
            enabled: true,
            experimentalChannel: true,  // Enables TCPRoute
          },
        },
        // TODO: Enable this
        // ocsp: { enabled: true },

        ports: {
          web: {
            hostPort: 80,
            http: { redirections: { entryPoint: {
              to: 'websecure',
              scheme: 'https',
              permanent: true,
            } } },
          },
          websecure: { hostPort: 443 },
          ssh: {
            containerPort: 2222,
            exposedPort: 2222,
            hostPort: 2222,
            port: 2222,
            protocol: 'TCP',
            expose: { default: true },
          },
        },
      },
    }),

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
      dnsNames: ['*.vpn.dzerv.art', '*.dzerv.art', 'dzerv.art'],
      // dnsNames: ['dzerv.art'],
    },
  },


  traefikNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-traefik')
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
} + middleware + anubis
