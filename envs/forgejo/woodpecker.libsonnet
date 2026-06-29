local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

{
  // Split the runners ns
  woodpeckerNS: k.core.v1.namespace.new('woodpecker'),

  woodpecker:
    helm.template('woodpecker', '../../charts/woodpecker', {
      namespace: 'forgejo',
      values: {
        fullnameOverride: 'woodpecker',
        agent: {
          networkPolicy: {
            enabled: true,
            egress: {
              // The chart's default apiserver rule uses an ipBlock CIDR, which
              // doesn't match Cilium's reserved kube-apiserver identity. Drop it
              // and rely on the CiliumNetworkPolicy below instead.
              apiserver: null,
            },
          },
          mapAgentSecret: false,
          extraSecretNamesForEnvFrom: ['woodpecker-agent-op'],
          env: {
            TZ: timezone,
            // Scratch volumes for the pipeline pods the agent spawns: 1-replica
            // v1 + Delete reclaim (longhorn-throwaway). RWX already on by default.
            WOODPECKER_BACKEND_K8S_STORAGE_CLASS: 'longhorn-throwaway',
          },
        },
        server: {
          networkPolicy: {
            enabled: true,
            ingress: {
              http: [{
                podSelector: { matchLabels: { app: 'forgejo' } },
              }],
            },
            egress: {
              extra: [{
                ports: [{ port: 80, protocol: 'TCP' }],
                to: [{
                  podSelector: { matchLabels: { app: 'forgejo' } },
                }],
              }],
            },
          },
          ingress: ingress.hostObj('ci.vpn.dzerv.art'),
          createAgentSecret: false,
          extraSecretNamesForEnvFrom: [
            'woodpecker-agent-op',
            'woodpecker-server-op',
          ],
          env: {
            WOODPECKER_HOST: 'https://ci.vpn.dzerv.art',
            WOODPECKER_OPEN: 'false',
            WOODPECKER_ADMIN: 'dzervas',

            WOODPECKER_FORGEJO: 'true',
            WOODPECKER_FORGEJO_URL: 'http://forgejo',
            // WOODPECKER_EXPERT_FORGE_OAUTH_HOST: 'https://git.vpn.dzerv.art/',
            WOODPECKER_FORCE_IGNORE_SERVICE_FAILURE: 'false',

            WOODPECKER_EXPERT_WEBHOOK_HOST: 'http://woodpecker-server',

            TZ: timezone,
          },
        },
      },
    }),

  woodpeckerAgentSecret: opsecretLib.new('woodpecker-agent'),
  woodpeckerServerSecret: opsecretLib.new('woodpecker-server'),

  // CiliumNetworkPolicy to allow agent egress to kube-apiserver.
  // Standard NetworkPolicy ipBlock CIDR rules don't match Cilium's
  // reserved kube-apiserver identity, so we need an explicit entity allow.
  woodpeckerAgentApiserverEgress: {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      name: 'woodpecker-agent-apiserver-egress',
      namespace: 'forgejo',
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'app.kubernetes.io/instance': 'woodpecker',
          'app.kubernetes.io/name': 'agent',
        },
      },
      egress: [{
        toEntities: ['kube-apiserver'],
      }],
    },
  },
}
