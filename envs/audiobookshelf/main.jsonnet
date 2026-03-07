local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local service = k.core.v1.service;

local domain = 'audiobooks.dzerv.art';

{
  namespace:
    k.core.v1.namespace.new('audiobookshelf')
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),

  audiobookshelf:
    helm.template('audiobookshelf', '../../charts/audiobookshelf', {
      namespace: $.namespace.metadata.name,
      values: {
        ingress: ingress.hostObj(domain, ingress.magicentryAnnotations('Audiobookshelf', 'audiobooks,public')),
        podLabels: {
          'magicentry.rs/enable': 'true',
        },
        persistence: {
          enabled: true,
          storageClass: 'linstor',
          podcasts: { size: '1Gi' },
          audiobooks: { size: '100Gi' },
        },
      },
    })
    + {
      pod_audiobookshelf_test_connection: {},
      service_audiobookshelf+:
        service.metadata.withLabels({ 'magicentry.rs/enable': 'true' })
        + service.metadata.withAnnotations({
          'magicentry.rs/name': 'Audiobooks',
          'magicentry.rs/url': 'https://' + domain,
          'magicentry.rs/realms': 'public,audiobooks',
          'magicentry.rs/auth_url_origins': 'https://' + domain,
          'magicentry.rs/oidc_redirect_urls': 'https://' + domain,
        }),
    },

  // audiobookrequest: dockerService.new('audiobookrequest', 'markbeep/audiobookrequest', {
  //   namespace: $.namespace.metadata.name,
  //   fqdn: 'add.' + domain,
  //   ports: [8000],
  //   labels: {
  //     managed_by: 'terraform',
  //     service: 'audiobookrequest',
  //   },
  //   pvs: {
  //     '/config': {
  //       name: 'config',
  //       size: '512Mi',
  //     },
  //   },
  //   env: {
  //     TZ: timezone,
  //   },
  // }),
}
