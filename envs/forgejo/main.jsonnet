local woodpecker = import './woodpecker.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local statefulSet = k.apps.v1.statefulSet;

local image = 'codeberg.org/forgejo/forgejo:15-rootless';

{
  forgejo:
    lab.new('forgejo', image)
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/var/lib/gitea', { name: 'data', size: '10Gi', storageClassName: 'longhorn' })
    + lab.withPV('/etc/gitea', { name: 'config', size: '128Mi', storageClassName: 'longhorn' })
    + lab.withVpnHttp(80, 'git.vpn.dzerv.art', [
      '10.200.0.0/16',  // Cilium cluster-pool Pod CIDR
      '10.20.30.0/24',  // The nodes to be able to download images
    ])
    + lab.withPublicTCP(2222, 'ssh')
    + lab.withEnv({
      FORGEJO__server__HTTP_PORT: '80',
      // Git clone/API and package registry clients use verified TLS
      FORGEJO__server__ROOT_URL: 'https://git.vpn.dzerv.art',
      // FORGEJO__server__SSH_PORT: '2222',
      FORGEJO__server__SSH_DOMAIN: 'git.vpn.dzerv.art',

      // Apply this disablement before enabling Woodpecker publication: no competing publisher
      FORGEJO__actions__ENABLED: 'false',
      FORGEJO__service__REQUIRE_SIGNIN_VIEW: 'false',

      FORGEJO__webhook__ALLOWED_HOST_LIST: 'woodpecker-server,ntfy.ntfy.svc',
      TZ: timezone,
    })
    // Source retirement does not authorize pruning old runner/cache/BuildKit namespaces or PVCs
    // Pause CI, apply Forgejo disablement, install Woodpecker guards/network/cache BEFORE agents
    // Inspect tk diff envs/forgejo; preserve forge data/config PVCs and archive old CI state before cleanup
    + { workload+: statefulSet.mapContainers(function(c) c { imagePullPolicy: 'Always' }) },
} + woodpecker
