local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

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
      DATABASE_URL: { name: 'affine-postgres', key: 'postgres_url' },
    })
  ,

  redis:
    lab.new('redis', 'redis')
    + lab.withNamespace('affine')
    + lab.withPort({ port: 6379 })
    + lab.withEmptyDir('/data'),

  passwords:
    externalSecret.new('affine-postgres')
    // Regenerate only when this ExternalSecret is deliberately changed.
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }])
    + externalSecret.spec.target.template.withData({
      password: '{{ .password }}',
      postgres_url: 'postgresql://affine:{{ .password | urlquery }}@shared-rw.postgres.svc:5432/affine',
    }),
}
