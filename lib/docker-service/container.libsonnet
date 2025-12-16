local k = import 'k.libsonnet';

local container = k.core.v1.container;
local port = k.core.v1.containerPort;
local volume = k.core.v1.volume;
local volumeMount = k.core.v1.volumeMount;

{
  new(name, image, user=1000, command=null, args=null, env={}, pvs={}, ports=[])::
    local hasPvs = std.length(std.objectFields(pvs)) > 0;

    // Build volumes
    // Takes an object of { "/mount/path": { name: "pvc-name", size: "1Gi", read_only: true, empty_dir: true } }
    // and produces a list of volumes
    local volumes = std.map(
      function(mountPath)
        local volumeName = if std.objectHas(pvs[mountPath], 'name') then
          pvs[mountPath].name
        else
          '%s-%s' % [name, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')];

        if std.objectHas(pvs[mountPath], 'empty_dir') && pvs[mountPath].empty_dir then
          volume.emptyDir(volumeName)
        else
          volume.fromPersistentVolumeClaim(volumeName, volumeName),
      std.objectFields(pvs)
    );

    // Build volume mounts
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

    // Build env vars
    local envVars = [
      { name: key, value: env[key] }
      for key in std.objectFields(env)
    ];

    {
      volumes: volumes,
      vms: volumeMounts,
      container: container.new(name, image)
                 + container.withPorts(std.map(port.new, ports))
                 + container.withImagePullPolicy('Always')
                 + (if std.length(volumeMounts) > 0 then container.withVolumeMounts(volumeMounts) else {})
                 + (if std.length(envVars) > 0 then container.withEnv(envVars) else {})
                 + container.securityContext.withRunAsNonRoot(true)
                 + container.securityContext.withRunAsUser(user)
                 + container.securityContext.withRunAsGroup(user)
                 + container.securityContext.withAllowPrivilegeEscalation(false)
                 + container.securityContext.capabilities.withDrop(['ALL']),
    },
}


// container.new(name, image)
// + container.withPorts([ port.newNamed(port, "http") ])
// + container.withImagePullPolicy("Always")
// + (if std.length(volumeMounts) > 0 then container.withVolumeMounts(volumeMounts) else {})
// + (if std.length(envVars) > 0 then container.withEnv(envVars) else {})
// + container.securityContext.withRunAsNonRoot(true)
// + container.securityContext.withRunAsUser(runAsUser)
// + container.securityContext.withRunAsGroup(runAsUser)
// + container.securityContext.withAllowPrivilegeEscalation(false)
// + container.securityContext.capabilities.withDrop([ "ALL" ]),
