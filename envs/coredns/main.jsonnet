local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

{
  coredns: helm.template('coredns', '../../charts/coredns', {
    namespace: 'coredns',
    values: {
      isClusterService: false,
      securityContext: {
        capabilities: {
          add: [],
          drop: ['ALL'],
        },
      },

      servers: [{
        zones: [{
          zone: '.',
          scheme: 'https://',
        }],
        port: 453,
        plugins: [
          { name: 'errors' },
          { name: 'ready' },
          { name: 'health', configBlock: 'lameduck 10s' },
          { name: 'cache', parameters: 30 },
          { name: 'loop' },
          { name: 'reload' },
          { name: 'loadbalance' },

          {
            name: 'https',
          },
        ],
      }],
    },
  }),
}
