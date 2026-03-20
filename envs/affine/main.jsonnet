local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  affine:
    lab.new('affine', 'ghcr.io/dzervas/affine')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    // + lab.withFqdn('notes.vpn.dzerv.art')
    // + lab.withPort({ port: 3010 })
    + lab.withVpnHttp(3010, fqdn='docs.vpn.dzerv.art')
    + lab.withPV('/home/node/.affine/storage', { name: 'affine-storage', size: '10Gi' })
    + lab.withPV('/home/node/.affine/config', { name: 'affine-config', size: '1Gi' })
    + lab.withEnv({
      AFFINE_INDEXER_ENABLED: 'true',
      AFFINE_SERVER_EXTERNAL_URL: 'https://notes.vpn.dzerv.art',
      REDIS_SERVER_HOST: 'redis',
    })
    + lab.withInitContainer({
      name: 'migrations',
      image: 'ghcr.io/dzervas/affine',
      command: ['sh', '-c', 'node ./scripts/self-host-predeploy.js'],
    })
    + lab.withSecretEnv({
      DATABASE_URL: { name: 'affine-secrets-op', key: 'postgres_url' },
    })
  ,

  redis:
    lab.new('redis', 'redis')
    + lab.withNamespace('affine')
    + lab.withPort({ port: 6379 })
    + lab.withEmptyDir('/data'),

  postgres:
    lab.new('postgres', 'pgvector/pgvector:pg16')
    + lab.withNamespace('affine')
    + lab.withRunAsUser(999)
    + lab.withType('StatefulSet')
    + lab.withPort({ port: 5432 })
    + lab.withPV('/var/lib/postgresql', { size: '2Gi' })
    + lab.withEnv({
      POSTGRES_USER: 'affine',
      POSTGRES_DB: 'affine',
      POSTGRES_INITDB_ARGS: '--data-checksums',
    })
    + lab.withSecretEnv({
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
      postgres_url: 'postgres://affine:{{ .password }}@postgres:5432/affine',
    }),
}
