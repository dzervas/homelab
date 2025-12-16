local k = import 'k.libsonnet';
local pvc = k.core.v1.persistentVolumeClaim;

{
  new(name, namespace, mountPath, pvcConfig, labels)::
    local pvcName = if std.objectHas(pvcConfig, 'name') then pvcConfig.name else '%s-%s' % [name, std.strReplace(std.lstripChars(mountPath, '/'), '/', '-')];

    pvc.new(pvcName)
    + pvc.metadata.withNamespace(namespace)
    + pvc.spec.withAccessModes(if std.objectHas(pvcConfig, 'access_modes') then pvcConfig.access_modes else ['ReadWriteOnce'])
    + pvc.spec.resources.withRequests({ storage: pvcConfig.size })
    + pvc.metadata.withLabels(labels),

  // Build all PVCs from pvs config
  build(name, namespace, pvs, labels)::
    std.filterMap(
      function(mountPath) !(std.objectHas(pvs[mountPath], 'empty_dir') && pvs[mountPath].empty_dir),
      function(mountPath) $.new(name, namespace, mountPath, pvs[mountPath], labels),
      std.objectFields(pvs)
    ),
}
