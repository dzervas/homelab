local k = import 'k.libsonnet';

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

{
  new(name, cfg)::
    service.new(
      name,
      cfg.labels,
      std.map(
        function(port) servicePort.new(port, port),
        cfg.ports
      )
    )
    + service.metadata.withNamespace(cfg.namespace)
    + service.metadata.withLabels(cfg.labels),
}
