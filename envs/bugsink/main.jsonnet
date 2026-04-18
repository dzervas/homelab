local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  // To create the initial user: bugsink-manage createsuperuser --username dzervas --email dzervas@dzervas.gr
  bugsink:
    lab.new('bugsink', 'bugsink/bugsink')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/data', { name: 'bugsink', size: '128Mi', storageClassName: 'longhorn' })
    + lab.withEnv({
        PORT: '8000',
        TZ: timezone,
        TIME_ZONE: timezone,
        DATABASE_PATH: '/data/bugsink.sqlite',
        BEHIND_HTTPS_PROXY: 'true',
        USE_X_FORWARDED_HOST: 'true',
        USE_X_REAL_IP: 'true',
        BASE_URL: 'https://errors.dzerv.art/',
      })
    + lab.withSecretEnv({ SECRET_KEY: { name: 'bugsink-secret-key', key: 'SECRET_KEY'}, })
    + lab.withPublicHttp(8000, 'errors.dzerv.art'),

  secretKey:
    externalSecret.new('bugsink-secret-key')
    + externalSecret.spec.target.template.withData({ SECRET_KEY: '{{ .password }}' })
    + externalSecret.spec.withDataFrom([{
        sourceRef: {
          generatorRef: {
            apiVersion: 'generators.external-secrets.io/v1alpha1',
            kind: 'ClusterGenerator',
            name: 'password',
          },
        },
      }]),
}
