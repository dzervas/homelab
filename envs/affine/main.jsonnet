local lab = import 'labsonnet.libsonnet';

{
  affine:
    lab.new('affine', 'git.vpn.dzerv.art/dzervas/homelab/affine:latest')
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({ forgejoCreds: 'enabled' })
    + lab.withImagePullSecrets(['forgejo-cluster-secret'])
    + lab.withType('StatefulSet')
    + lab.withPublicHttp(3010, fqdn='plan.dzerv.art')
    + lab.withPV('/home/node/.affine/storage', { name: 'affine-storage', size: '10Gi' })
    + lab.withPV('/home/node/.affine/config', { name: 'affine-config', size: '1Gi' })
    + lab.withEnv({
      AFFINE_INDEXER_ENABLED: 'true',
      AFFINE_SERVER_EXTERNAL_URL: 'https://plan.dzerv.art',
      REDIS_SERVER_HOST: 'redis',
    })
    + lab.withInitContainer({
      name: 'migrations',
      image: 'git.vpn.dzerv.art/dzervas/homelab/affine:latest',
      command: ['sh', '-c', 'node ./scripts/self-host-predeploy.js'],
    })
    // TODO: Install Stakater Reloader before automating database password rotation.
    + lab.withSecretEnv({
      DATABASE_URL: { name: 'affine-postgres', key: 'uri' },
    })
  ,

  redis:
    lab.new('redis', 'redis')
    + lab.withNamespace('affine')
    + lab.withPort({ port: 6379 })
    + lab.withEmptyDir('/data'),
}
