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

        ingressClass: {
          name: 'vpn',
          isDefaultClass: false,
        },
        // gatewayClass: {
        //   name: 'vpn',
        // },

        api: { enabled: false },
        providers: {
          kubernetesCRD: { enabled: false },
          kubernetesIngress: { enabled: true },
          // kubernetesGateway: { enabled: true },
        },
        global: {
          checkNewVersion: false,
          sendAnonymousUsage: false,
        },

        ports: {
          web: {
            port: 7080,
            containerPort: 7080,
            exposedPort: 7080,
            hostPort: 7080,
          },
          websecure: {
            port: 7443,
            containerPort: 7443,
            exposedPort: 7443,
            hostPort: 7443,
          },
        },

        redis: { cluster: false },
      },
    }),
}
