local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local lab = import 'labsonnet.libsonnet';

{
  knot:
    lab.new('knot', 'atcr.io/tangled.org/knot')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withPV('/home/git', { name: 'data', size: '10Gi' })
    + lab.withPublicHttp(3000, 'knot.dzerv.art')
    + lab.withEnv({
      KNOT_SERVER_HOSTNAME: 'knot.dzerv.art',
      KNOT_SERVER_OWNER: 'did:plc:xo4u5624x45ujhxze4hjbm7n',
      KNOT_SERVER_PORT: '3000',
    }),
}
