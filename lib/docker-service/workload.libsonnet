// TODO: Disable automatic SA mounting to pods
local container = import 'container.libsonnet';
local k = import 'k.libsonnet';
local pvcLib = import 'pvc.libsonnet';

local port = k.core.v1.containerPort;
local volumeMount = k.core.v1.volumeMount;
local volume = k.core.v1.volume;
local pvc = k.core.v1.persistentVolumeClaim;

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
    local workload = if cfg.type == 'Deployment' then k.apps.v1.deployment else k.apps.v1.statefulSet;
    local volumeSpec = if cfg.type == 'Deployment' then
      // Give the deployment volumes as they come from the containers function
      workload.spec.template.spec.withVolumes(containersResult.volumes)
    else
      // Based on the returned volumes from the containers function, generate PVC templates for the stateful set
      workload.spec.withVolumeClaimTemplates(pvcLib.build(name, cfg.namespace, cfg.pvs, cfg.labels));

    workload.new(
      name=name,
      replicas=cfg.replicas,
      containers=[containersResult.container]
    )
    + volumeSpec
    + workload.metadata.withNamespace(cfg.namespace)
    + (if std.startsWith(image, 'ghcr.io/dzervas/') then workload.spec.template.spec.withImagePullSecrets([{ name: 'ghcr-cluster-secret' }]) else {})
    + workload.spec.template.spec.securityContext.withFsGroup(cfg.runAsUser)
    + workload.spec.template.spec.securityContext.withRunAsNonRoot(true)
    // "Mixin" to use the default "name" label as well
    + workload.spec.template.metadata.withLabelsMixin(cfg.labels)
    + workload.spec.selector.withMatchLabelsMixin(cfg.labels),
}
