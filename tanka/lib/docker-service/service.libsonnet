local k = import "k.libsonnet";

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

{
  new(name, cfg)::
    service.new(
      name,
      cfg.labels,
      [ servicePort.newNamed("http", cfg.port, cfg.port) ]
    )
    + service.metadata.withNamespace(cfg.namespace)
    + service.metadata.withLabels(cfg.labels),
}
