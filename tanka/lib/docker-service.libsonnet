local k = import "k.libsonnet";
local namespace = k.core.v1.namespace;

local pvcLib = import "docker-service/pvc.libsonnet";
local deploymentLib = import "docker-service/deployment.libsonnet";
local serviceLib = import "docker-service/service.libsonnet";
local ingressLib = import "docker-service/ingress.libsonnet";

{
  new(name, image, config={})::
    local defaults = {
      namespace: name,
      port: 80,
      replicas: 1,
      fqdn: null,
      pvs: {},
      env: {},
      runAsUser: 1000,
      ingressEnabled: true,
      ingressAnnotations: {},
      labels: {
        app: name,
        "app.kubernetes.io/name": name,
      },
    };
    local cfg = defaults + config;

    {
      namespace: namespace.new(cfg.namespace),
      deployment: deploymentLib.new(name, image, cfg),
      service: serviceLib.new(name, cfg),
    }
    + pvcLib.build(name, cfg.namespace, cfg.pvs, cfg.labels)
    + ingressLib.new(name, cfg),
}
