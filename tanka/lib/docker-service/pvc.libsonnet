local k = import "k.libsonnet";
local pvc = k.core.v1.persistentVolumeClaim;

{
  new(name, namespace, mountPath, pvcConfig, labels)::
    local pvcName = if std.objectHas(pvcConfig, "name") then pvcConfig.name else "%s-%s" % [ name, std.strReplace(std.lstripChars(mountPath, "/"), "/", "-") ];

    pvc.new(pvcName)
    + pvc.metadata.withNamespace(namespace)
    + pvc.spec.withAccessModes(if std.objectHas(pvcConfig, "access_modes") then pvcConfig.access_modes else [ "ReadWriteOnce" ])
    + pvc.spec.resources.withRequests({ storage: pvcConfig.size })
    + pvc.metadata.withLabels(labels),

  // Build all PVCs from pvs config
  build(name, namespace, pvs, labels)::
    if std.length(std.objectFields(pvs)) > 0 then {
      ["pvc-" + std.strReplace(mountPath, "/", "-")]: $.new(name, namespace, mountPath, pvs[mountPath], labels)
      for mountPath in std.objectFields(pvs)
    } else {},
}
