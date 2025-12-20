local k = import 'k.libsonnet';

local container = k.core.v1.container;
local port = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;
local envVar = k.core.v1.envVar;
local envVarSource = k.core.v1.envVarSource;

{
  new(name, image, user=1000, command=null, args=null, env={}, pvs={}, config_maps={}, ports=[], op_envs=[])::
    local hasPvs = std.length(std.objectFields(pvs)) > 0;

    // Build PVC / emptyDir volumes
    // Takes an object of { "/mount/path": { name: "pvc-name", size: "1Gi", read_only: true, empty_dir: true } }
    // and produces a list of volumes
    local volumes = std.map(
      function(mountPath)
        local volumeName = if std.objectHas(pvs[mountPath], 'name') then
          pvs[mountPath].name
        else
          '%s-%s' % [name, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')];

        if std.objectHas(pvs[mountPath], 'empty_dir') && pvs[mountPath].empty_dir then
          volume.fromEmptyDir(volumeName)
        else
          volume.fromPersistentVolumeClaim(volumeName, volumeName),
      std.objectFields(pvs)
    );

    // Build configMap volumes from { mountPath: "configmap[:rw]" }
    local configMapVolumes = std.map(
      function(mountPath)
        local value = config_maps[mountPath];
        local cmName = std.split(value, ':')[0];
        volume.fromConfigMap(cmName, cmName),
      std.objectFields(config_maps)
    );

    // Build volume mounts for PVCs / emptyDir
    local volumeMounts = std.map(
      function(mountPath)
        local volumeName = if std.objectHas(pvs[mountPath], 'name') then
          pvs[mountPath].name
        else
          '%s-%s' % [name, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')];
        local readOnly = std.objectHas(pvs[mountPath], 'read_only') && pvs[mountPath].read_only;

        volumeMount.new(volumeName, mountPath, readOnly),
      std.objectFields(pvs)
    );

    local opEnvVars = std.map(
      function(envVarName)
        envVar.withName(envVarName)
        + envVar.valueFrom.secretKeyRef.withName(name + '-op')
        + envVar.valueFrom.secretKeyRef.withKey(envVarName),
      op_envs
    );

    {
      volumes: volumes,
      container:
        container.new(name, image)
        + container.withPorts(std.map(port.new, ports))
        + container.withImagePullPolicy('Always')
        + container.withVolumeMounts(volumeMounts)
        + container.withEnv(opEnvVars)
        + container.withEnvMap(env)
        + (if command != null then container.withCommand(command) else {})
        + (if args != null then container.withArgs(args) else {})
        + container.securityContext.withRunAsNonRoot(true)
        + container.securityContext.withRunAsUser(user)
        + container.securityContext.withRunAsGroup(user)
        + container.securityContext.withAllowPrivilegeEscalation(false)
        + container.securityContext.capabilities.withDrop(['ALL']),
    },
}
