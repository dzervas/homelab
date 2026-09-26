local runner = import './runner.libsonnet';
local woodpecker = import './woodpecker.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local statefulSet = k.apps.v1.statefulSet;
local container = k.core.v1.container;

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
      // FORGEJO__server__SSH_PORT: '2222',
      FORGEJO__server__SSH_DOMAIN: 'git.vpn.dzerv.art',

      FORGEJO__actions__ENABLED: 'true',

      FORGEJO__webhook__ALLOWED_HOST_LIST: 'woodpecker-server',
      TZ: timezone,
    })
    // Idempotent offline registration of the shared forgejo-runner identity.
    // A sidecar rather than an init container so a failure (e.g. pending DB
    // migrations) retries without blocking Forgejo from starting.
    + lab.withSecretMount('/run/secrets/forgejo-runner', 'forgejo-runner')
    + lab.withInitContainer(
      container.new('runner-register', image)
      + container.withImagePullPolicy('Always')
      + container.withRestartPolicy('Always')  // Makes it a sidecar
      + container.withCommand(['sh', '-c'])
      + container.withArgs([|||
        until forgejo forgejo-cli actions register --name k8s --keep-labels \
          --secret-file /run/secrets/forgejo-runner/token; do
          echo 'runner registration failed, retrying...'
          sleep 10
        done
        while true; do sleep 3600; done
      |||])
    )
    + { workload+: statefulSet.mapContainers(function(c) c { imagePullPolicy: 'Always' }) },
} + woodpecker + runner
