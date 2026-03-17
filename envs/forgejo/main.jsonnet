local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local timezone = import 'helpers/timezone.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local lab = import 'labsonnet.libsonnet';

{
  forgejo:
    lab.new('forgejo', 'codeberg.org/forgejo/forgejo:13-rootless')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/var/lib/gitea', { name: 'data', size: '10Gi' })
    + lab.withPV('/etc/gitea', { name: 'config', size: '128Mi' })
    + lab.withVpnHttp(3000, 'git.vpn.dzerv.art')
    + lab.withEnv({ TZ: timezone }),

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
          networkPolicy: { enabled: true },
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
            WOODPECKER_FORGEJO_URL: 'https://git.vpn.dzerv.art',

            TZ: timezone,
          },
        },
      },
    }),

  woodpeckerAgentSecret: opsecretLib.new('woodpecker-agent'),
  woodpeckerServerSecret: opsecretLib.new('woodpecker-server'),
}
