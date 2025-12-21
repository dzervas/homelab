local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'romm';
local domain = 'dzerv.art';

{
  // There's an OIDC bug: https://github.com/rommapp/romm/issues/2732
  romm:
    dockerService.new('romm', 'rommapp/romm', {
      type: 'Deployment',
      namespace: namespace,
      fqdn: 'games.' + domain,
      ports: [8080],
      ingressAnnotations: ingress.oidcAnnotations('romm') + {
        'nginx.ingress.kubernetes.io/proxy-body-size': '1g',
      },
      env: {
        TZ: timezone,
        DB_HOST: 'mariadb-headless',
        DB_NAME: 'romm',
        DB_USER: 'romm',
        ROMM_PORT: '8080',
        OIDC_ENABLED: 'true',
        OIDC_PROVIDER: 'magicentry',
        OIDC_REDIRECT_URI: 'https://games.dzerv.art/api/oauth/openid',
        OIDC_SERVER_APPLICATION_URL: 'http://magicentry.auth.svc.cluster.local:8080',
      },
      op_envs: {
        OIDC_CLIENT_ID: 'client-id',
        OIDC_CLIENT_SECRET: 'client-secret',
        DB_PASSWD: 'mariadb-password',
        ROMM_AUTH_SECRET_KEY: 'auth-secret-key',
        SCREENSCRAPER_USER: 'screenscraper-user',
        SCREENSCRAPER_PASSWORD: 'screenscraper-password',
        RETROACHIEVEMENTS_API_KEY: 'retroachievements-api-key',
        STEAMGRIDDB_API_KEY: 'steamgriddb-api-key',
      },
      pvs: {
        '/romm/library': {
          name: 'roms',
          size: '30Gi',
        },
        '/romm/assets': {
          name: 'saves',
          size: '5Gi',
        },
        '/romm/resources': {
          name: 'metadata',
          size: '10Gi',
        },
        '/redis-data': {
          name: 'cache',
          size: '5Gi',
        },
      },
      config_maps: {
        '/romm/config': 'romm-config:rw',
      },
    })
    + {
      workload+: {
        spec+: {
          template+: {
            metadata+: {
              labels+: {
                'magicentry.rs/enable': 'true',
              },
            },
          },
        },
      },
    },

  rommConfig:
    k.core.v1.configMap.new('romm-config')
    + k.core.v1.configMap.metadata.withNamespace(namespace)
    + k.core.v1.configMap.withData({
      'config.yml': std.manifestYamlDoc({}),
    }),

  mariadb: helm.template('mariadb', '../../charts/mariadb', {
    namespace: namespace,
    values: {
      image: {
        repository: 'bitnamilegacy/mariadb',
      },
      auth: {
        database: 'romm',
        username: 'romm',
        existingSecret: 'romm-op',
      },
      primary: {
        persistence: { size: '1Gi' },
      },
    },
  }),
}
