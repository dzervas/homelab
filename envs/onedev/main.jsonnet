local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local helm = tk.helm.new(std.thisFile);

{
  namespace:
    k.core.v1.namespace.new('onedev')
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),

  onedev: helm.template('onedev', '../../charts/onedev', {
    namespace: $.namespace.metadata.name,
    values: {
      database: {
        type: 'postgresql',
        port: 5432,
        user: 'onedev',
      },

      ingress: ingress.hostString('dev.vpn.dzerv.art') + {
        className: 'traefik',
        tls: {
          enabled: true,
          secretName: 'dev-vpn-dzerv-art-cert',
        },
      },
      persistence: {
        enabled: true,
        size: '10Gi',
      },
    },
  }),
}
