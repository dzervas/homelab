local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'descheduler';

{
  namespace: k.core.v1.namespace.new(namespace),

  descheduler: helm.template(
    'descheduler',
    '../../charts/descheduler',
    {
      namespace: namespace,
      values: {
        serviceMonitor: { enabled: true },
      },
    },
  ),
}
