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
          networkPolicy: { enabled: true },
          mapAgentSecret: false,
          extraSecretNamesForEnvFrom: ['woodpecker-agent-op'],
          env: {
            TZ: timezone,
          },
        },
        server: {
          networkPolicy: {
            enabled: true,
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
            WOODPECKER_EXPERT_FORGE_OAUTH_HOST: 'https://git.vpn.dzerv.art/',
            WOODPECKER_FORCE_IGNORE_SERVICE_FAILURE: 'false',

            TZ: timezone,
          },
        },
      },
    }),

  woodpeckerAgentSecret: opsecretLib.new('woodpecker-agent'),
  woodpeckerServerSecret: opsecretLib.new('woodpecker-server'),
}
