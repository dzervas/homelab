local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'traefik';

{
  namespace:
    k.core.v1.namespace.new(namespace),
  // + k.core.v1.namespace.metadata.withLabels({
  //   'pod-security.kubernetes.io/enforce': 'privileged',
  //   'pod-security.kubernetes.io/enforce-version': 'latest',
  // }),

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
          name: 'vpn',
          isDefaultClass: false,
        },
        providers: {
          kubernetesCRD: { enabled: false },
          kubernetesIngress: { enabled: true },
        },

        ports: {
          web: {
            port: 7080,
            containerPort: 7080,
            exposedPort: 7080,
            hostPort: 7080,
            // hostIP: '127.0.0.1',
          },
          websecure: {
            port: 7443,
            containerPort: 7443,
            exposedPort: 7443,
            hostPort: 7443,
            // hostIP: '127.0.0.1',
          },
          traefik: {
            port: 7081,
            containerPort: 7081,
            exposedPort: 7081,
            hostPort: 7081,
            hostIP: '127.0.0.1',
          },
          metrics: {
            port: 7999,
            containerPort: 7999,
            exposedPort: 7999,
            hostPort: 7999,
            hostIP: '127.0.0.1',
          },
        },

        redis: { cluster: false },
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
        port: 7080,
        protocol: 'TCP',
      }, {
        port: 7443,
        protocol: 'TCP',
      }],
    }]),
}
