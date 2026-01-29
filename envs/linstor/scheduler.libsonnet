local schedulerYaml = importstr 'linstor-scheduler-extender/deploy/linstor-scheduler.yaml';
local admissionYaml = importstr 'linstor-scheduler-extender/deploy/linstor-scheduler-admission.yaml';
local scheduler = std.parseYaml(schedulerYaml);
local admission = std.parseYaml(admissionYaml);

local targetNs = 'linstor';
local kubeSchedulerImage = 'registry.k8s.io/kube-scheduler:v1.33.6';  // Must match cluster version

// Replace namespace in subjects array (for RoleBindings/ClusterRoleBindings)
local replaceSubjectsNs(obj) =
  if std.objectHas(obj, 'subjects') then
    obj {
      subjects: [
        s { namespace: targetNs }
        for s in obj.subjects
        if std.objectHas(s, 'namespace')
      ] + [
        s
        for s in obj.subjects
        if !std.objectHas(s, 'namespace')
      ],
    }
  else
    obj;

// Handle RoleBinding that needs to stay in kube-system (extension-apiserver-authentication-reader)
local needsKubeSystem(obj) =
  obj.kind == 'RoleBinding' &&
  std.objectHas(obj, 'roleRef') &&
  obj.roleRef.name == 'extension-apiserver-authentication-reader';

// Fix namespace references throughout the object
local fixNamespaces(obj) =
  local withSubjects = replaceSubjectsNs(obj);
  if needsKubeSystem(obj) then
    // This RoleBinding must stay in kube-system to access the system Role
    withSubjects { metadata+: { namespace: 'kube-system' } }
  else if std.objectHas(obj.metadata, 'namespace') then
    withSubjects { metadata+: { namespace: null } }
  else
    withSubjects;

// Update kube-scheduler image to match cluster version
local updateSchedulerImage(obj) =
  if obj.kind == 'Deployment' && obj.metadata.name == 'linstor-scheduler' then
    obj {
      spec+: {
        template+: {
          spec+: {
            containers: [
              if std.startsWith(c.image, 'registry.k8s.io/kube-scheduler') then
                c { image: kubeSchedulerImage }
              else
                c
              for c in obj.spec.template.spec.containers
            ],
          },
        },
      },
    }
  else
    obj;

local processManifests(arr) = std.map(
  function(obj) updateSchedulerImage(fixNamespaces(obj)),
  arr
);

{
  scheduler: processManifests(scheduler),
  admission: processManifests(admission),
}
