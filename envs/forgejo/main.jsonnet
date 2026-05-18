local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';
local woodpecker = import './woodpecker.libsonnet';

{
  forgejo:
    lab.new('forgejo', 'codeberg.org/forgejo/forgejo:15-rootless')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/var/lib/gitea', { name: 'data', size: '10Gi', storageClassName: 'longhorn' })
    + lab.withPV('/etc/gitea', { name: 'config', size: '128Mi', storageClassName: 'longhorn' })
    + lab.withVpnHttp(3000, 'git.vpn.dzerv.art')
    + lab.withEnv({ TZ: timezone }),
} // + woodpecker
