local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'audiobookshelf';
local domain = 'dzerv.art';

{
  audiobookshelf: helm.template('audiobookshelf', '../../charts/audiobookshelf', {
    namespace: namespace,
    values: {
      ingress: ingress.hostObj('audiobooks.' + domain, ingress.magicentryAnnotations('Audiobookshelf', 'audiobooks,public')),
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
  }) + { pod_audiobookshelf_test_connection: {} },

  audiobookrequest: dockerService.new('audiobookrequest', 'markbeep/audiobookrequest', {
    namespace: namespace,
    fqdn: 'add.audiobooks.' + domain,
    ports: [8000],
    labels: {
      managed_by: 'terraform',
      service: 'audiobookrequest',
    },
    pvs: {
      '/config': {
        name: 'config',
        size: '512Mi',
      },
    },
    env: {
      TZ: timezone,
    },
  }),
}
