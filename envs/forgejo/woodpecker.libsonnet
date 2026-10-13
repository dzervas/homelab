local workers = import './woodpecker/agent.libsonnet';
local policy = import './woodpecker/policy.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local helm = tk.helm.new(std.thisFile);

{
  woodpecker:
    helm.template('woodpecker', '../../charts/woodpecker', {
      namespace: 'forgejo',
      values: {
        fullnameOverride: 'woodpecker',
        agent: { enabled: false },
        server: {
          networkPolicy: {
            enabled: true,
            ingress: {
              http: [{
                podSelector: { matchLabels: { app: 'forgejo' } },
              }],
            },
            egress: {
              extra: [
                {
                  ports: [{ port: 80, protocol: 'TCP' }],
                  to: [{
                    podSelector: { matchLabels: { app: 'forgejo' } },
                  }],
                },
                {
                  ports: [{ port: 10443, protocol: 'TCP' }],
                  to: [{
                    namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
                    podSelector: { matchLabels: {
                      'app.kubernetes.io/instance': 'traefik-traefik',
                      'app.kubernetes.io/name': 'traefik',
                    } },
                  }],
                },
              ],
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
            WOODPECKER_AUTHENTICATE_PUBLIC_REPOS: 'true',

            WOODPECKER_FORGEJO: 'true',
            WOODPECKER_FORGEJO_URL: 'http://forgejo',
            WOODPECKER_EXPERT_FORGE_OAUTH_HOST: 'https://git.vpn.dzerv.art',
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
      egress: [
        { toEntities: ['kube-apiserver'] },
        {
          toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
          toPorts: [{ ports: [{ port: '53', protocol: 'ANY' }] }],
        },
        {
          toEndpoints: [{ matchLabels: {
            'k8s:io.kubernetes.pod.namespace': 'forgejo',
            'k8s:app.kubernetes.io/instance': 'woodpecker',
            'k8s:app.kubernetes.io/name': 'server',
          } }],
          toPorts: [{ ports: [{ port: '9000', protocol: 'TCP' }] }],
        },
      ],
    },
  },
} + workers + policy
