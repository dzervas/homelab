local k = import "k.libsonnet";

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local port = k.core.v1.containerPort;
local volumeMount = k.core.v1.volumeMount;
local volume = k.core.v1.volume;

{
  new(name, image, cfg)::
    local hasPvs = std.length(std.objectFields(cfg.pvs)) > 0;

    // Build volumes
    local volumes = if hasPvs then [
      volume.fromPersistentVolumeClaim(
        if std.objectHas(cfg.pvs[mountPath], "name") then cfg.pvs[mountPath].name else "%s-%s" % [ name, std.strReplace(std.lstripChars(mountPath, "/"), "/", "-") ],
        if std.objectHas(cfg.pvs[mountPath], "name") then cfg.pvs[mountPath].name else "%s-%s" % [ name, std.strReplace(std.lstripChars(mountPath, "/"), "/", "-") ]
      )
      for mountPath in std.objectFields(cfg.pvs)
    ] else [];

    // Build volume mounts
    local volumeMounts = if hasPvs then [
      volumeMount.new(
        if std.objectHas(cfg.pvs[mountPath], "name") then cfg.pvs[mountPath].name else "%s-%s" % [ name, std.strReplace(std.lstripChars(mountPath, "/"), "/", "-") ],
        mountPath
      )
      + (if std.objectHas(cfg.pvs[mountPath], "read_only") && cfg.pvs[mountPath].read_only then volumeMount.withReadOnly(true) else {})
      for mountPath in std.objectFields(cfg.pvs)
    ] else [];

    // Build env vars
    local envVars = [
      { name: key, value: cfg.env[key] }
      for key in std.objectFields(cfg.env)
    ];

    deployment.new(
      name=name,
      replicas=cfg.replicas,
      containers=[
        container.new(name, image)
        + container.withPorts([ port.newNamed(cfg.port, "http") ])
        + container.withImagePullPolicy("Always")
        + (if std.length(volumeMounts) > 0 then container.withVolumeMounts(volumeMounts) else {})
        + (if std.length(envVars) > 0 then container.withEnv(envVars) else {})
        + container.securityContext.withRunAsNonRoot(true)
        + container.securityContext.withRunAsUser(cfg.runAsUser)
        + container.securityContext.withRunAsGroup(cfg.runAsUser)
        + container.securityContext.withAllowPrivilegeEscalation(false)
        + container.securityContext.capabilities.withDrop([ "ALL" ]),
      ]
    )
    + deployment.metadata.withNamespace(cfg.namespace)
    + (if std.length(volumes) > 0 then deployment.spec.template.spec.withVolumes(volumes) else {})
    + (if std.startsWith(image, "ghcr.io/dzervas/") then deployment.spec.template.spec.withImagePullSecrets([ { name: "ghcr-cluster-secret" } ]) else {})
    + deployment.spec.template.spec.securityContext.withFsGroup(cfg.runAsUser)
    + deployment.spec.template.spec.securityContext.withRunAsNonRoot(true)
    + deployment.spec.template.metadata.withLabels(cfg.labels)
    + deployment.spec.selector.withMatchLabels(cfg.labels),
}
