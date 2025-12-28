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
      config_maps=cfg.config_maps,
      secrets=cfg.secrets,
      ports=cfg.ports,
      op_envs=cfg.op_envs
    );
    local workload = if cfg.type == 'Deployment' then k.apps.v1.deployment else k.apps.v1.statefulSet;
    local volumeNameFor = function(mountPath)
      if std.objectHas(cfg.pvs[mountPath], 'name') then
        cfg.pvs[mountPath].name
      else
        '%s-%s' % [name, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')];

    local emptyDirVolumes = std.map(
      function(mountPath)
        volume.fromEmptyDir(volumeNameFor(mountPath)),
      std.filter(
        function(mountPath)
          std.objectHas(cfg.pvs[mountPath], 'empty_dir') && cfg.pvs[mountPath].empty_dir,
        std.objectFields(cfg.pvs)
      )
    );

    local volumeSpec = if cfg.type == 'Deployment' then
      // Give the deployment volumes as they come from the containers function
      workload.spec.template.spec.withVolumes(containersResult.volumes)
    else
      // For stateful sets, keep PVC templates and add only emptyDir volumes to the pod spec
      workload.spec.template.spec.withVolumes(emptyDirVolumes)
      + workload.spec.withVolumeClaimTemplates(pvcLib.build(name, cfg.namespace, cfg.pvs, cfg.labels));

    local configMaps = std.foldl(
      function(prev, configMap)
        // TODO: Add an option to use configMapVolumeMount to restart the container on config change
        local cmName = std.split(cfg.config_maps[configMap], ':')[0];
        local readOnly = !std.endsWith(cfg.config_maps[configMap], ':rw');

        prev + workload.configVolumeMount(
          cmName,
          configMap,
          volumeMountMixin=volumeMount.withReadOnly(readOnly),
          volumeMixin=volume.configMap.withDefaultMode(std.parseOctal(if readOnly then '444' else '666'))
        ),
      std.objectFields(cfg.config_maps),
      {}
    );

    workload.new(
      name=name,
      replicas=cfg.replicas,
      containers=[containersResult.container]
    )
    + volumeSpec
    + configMaps
    + workload.metadata.withNamespace(cfg.namespace)
    + (if std.startsWith(image, 'ghcr.io/dzervas/') then workload.spec.template.spec.withImagePullSecrets([{ name: 'ghcr-cluster-secret' }]) else {})
    + workload.spec.template.spec.securityContext.withFsGroup(cfg.runAsUser)
    + workload.spec.template.spec.securityContext.withRunAsNonRoot(true)
    // "Mixin" to use the default "name" label as well
    + workload.spec.template.metadata.withLabelsMixin(cfg.labels)
    + workload.spec.selector.withMatchLabelsMixin(cfg.labels),
}
