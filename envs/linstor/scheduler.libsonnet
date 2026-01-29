local schedulerYaml = importstr 'linstor-scheduler-extender/deploy/linstor-scheduler.yaml';
local admissionYaml = importstr 'linstor-scheduler-extender/deploy/linstor-scheduler-admission.yaml';
local scheduler = std.parseYaml(schedulerYaml);
local admission = std.parseYaml(admissionYaml);

local removeNamespace(arr) = std.map(
  function(obj) obj { metadata+: { namespace: null } },
  arr
);

{
  scheduler: removeNamespace(scheduler),
  admission: removeNamespace(admission),
}
