local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);
local affinity = import 'helpers/affinity.libsonnet';

{
  operator: helm.template('piraeus', '../../charts/piraeus', {
    values: {
      installCRDs: true,
      operator: {
        options: { zapDevel: false },
      },
      tls: {
        certManagerIssuerRef: {
          name: 'selfsigned',
          kind: 'ClusterIssuer',
        },
      },
      tolerations: [],
      affinity: affinity.avoidHomelab,
    },
  }),
}
