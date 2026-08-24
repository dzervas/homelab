local woodpecker = import './woodpecker.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

{
  forgejo:
    lab.new('forgejo', 'codeberg.org/forgejo/forgejo:15-rootless')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/var/lib/gitea', { name: 'data', size: '10Gi', storageClassName: 'longhorn' })
    + lab.withPV('/etc/gitea', { name: 'config', size: '128Mi', storageClassName: 'longhorn' })
    + lab.withVpnHttp(80, 'git.vpn.dzerv.art')
    + {
      'middleware-vpn-80'+: {
        spec: { ipAllowList: { sourceRange: [
          '100.100.50.0/24',  // headscale tailnet
          '10.200.0.0/16',  // Cilium cluster-pool Pod CIDR
          '10.20.30.0/24',
        ] } },
      },
    }
    + lab.withPublicTCP(2222, 'ssh')
    + lab.withEnv({
      FORGEJO__server__HTTP_PORT: '80',
      // FORGEJO__server__SSH_PORT: '2222',
      FORGEJO__server__SSH_DOMAIN: 'dzerv.art',

      FORGEJO__actions__ENABLED: 'false',

      FORGEJO__webhook__ALLOWED_HOST_LIST: 'woodpecker-server',
      TZ: timezone,
    }),
} + woodpecker
