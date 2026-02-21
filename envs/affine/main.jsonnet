local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local k = import 'k.libsonnet';
local labsonnet = import 'labsonnet/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  affine:
    labsonnet.new('affine', 'ghcr.io/dzervas/affine')
    + labsonnet.withCreateNamespace()
    + labsonnet.withType('StatefulSet')
    + labsonnet.withPort({ port: 3010 })
    + labsonnet.withPV('/root/.affine/storage', { name: 'affine-storage', size: '10Gi' })
    + labsonnet.withPV('/root/.affine/config', { name: 'affine-config', size: '1Gi' })
    // + labsonnet.withEnv('AFFINE_INDEXER_ENABLED', 'false')
    + labsonnet.withEnv({ REDIS_SERVER_HOST: 'redis' })
    + labsonnet.withInitContainer({
      name: 'migrations',
      image: 'ghcr.io/toeverything/affine:stable',
      command: ['sh', '-c', 'node ./scripts/self-host-predeploy.js'],
    })
    + labsonnet.withSecretEnv({
      DATABASE_SERVER_URL: { name: 'affine-secrets-op', key: 'postgres_url' },
    })
  ,

  redis:
    labsonnet.new('redis', 'redis')
    + labsonnet.withNamespace('affine')
    + labsonnet.withPort({ port: 6379 }),

  postgres:
    labsonnet.new('postgres', 'pgvector/pgvector:pg16')
    + labsonnet.withNamespace('affine')
    + labsonnet.withType('StatefulSet')
    + labsonnet.withPort({ port: 5432 })
    + labsonnet.withPV('/var/lib/postgresql/data', { size: '2Gi' })
    + labsonnet.withEnv({
      POSTGRES_USER: 'affine',
      POSTGRES_DB: 'affine',
      POSTGRES_INITDB_ARGS: '--data-checksums',
      // + labsonnet.withEnv('POSTGRES_HOST_AUTH_METHOD', 'trust')
    })
    + labsonnet.withSecretEnv({
      POSTGRES_PASSWORD: { name: 'affine-secrets-op', key: 'password' },
    })
  ,

  passwords:
    externalSecret.new('affine-secrets-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'affine' } }])
    + externalSecret.spec.target.template.withData({
      password: '{{ .password }}',
      postgres_url: 'postgres://affine@{{ .password }}:5432/affine',
    }),
}
