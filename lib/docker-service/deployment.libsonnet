// TODO: Disable automatic SA mounting to pods
local container = import 'container.libsonnet';
local k = import 'k.libsonnet';

local deployment = k.apps.v1.deployment;
local port = k.core.v1.containerPort;
local volumeMount = k.core.v1.volumeMount;
local volume = k.core.v1.volume;

{
  new(name, image, cfg)::
    local containersResult = container.new(
      name=name,
      image=image,
      user=cfg.runAsUser,
      command=cfg.command,
      args=cfg.args,
      env=cfg.env,
      pvs=cfg.pvs,
      ports=cfg.ports,
    );
    deployment.new(
      name=name,
      replicas=cfg.replicas,
      containers=[containersResult.container]
    )
    + deployment.metadata.withNamespace(cfg.namespace)
    + (if std.length(containersResult.volumes) > 0 then deployment.spec.template.spec.withVolumes(containersResult.volumes) else {})
    + (if std.startsWith(image, 'ghcr.io/dzervas/') then deployment.spec.template.spec.withImagePullSecrets([{ name: 'ghcr-cluster-secret' }]) else {})
    + deployment.spec.template.spec.securityContext.withFsGroup(cfg.runAsUser)
    + deployment.spec.template.spec.securityContext.withRunAsNonRoot(true)
    + deployment.spec.template.metadata.withLabels(cfg.labels)
    + deployment.spec.selector.withMatchLabels(cfg.labels),
}
