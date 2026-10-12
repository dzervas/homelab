local k = import 'k.libsonnet';

local validatingAdmissionPolicy = k.admissionregistration.v1.validatingAdmissionPolicy;
local validatingAdmissionPolicyBinding = k.admissionregistration.v1.validatingAdmissionPolicyBinding;
local serviceAccount = k.core.v1.serviceAccount;

// Capabilities are perceived only inside gVisor, not granted to the host
// https://gvisor.dev/docs/tutorials/docker-in-gvisor/
local dindCapabilities = [
  'AUDIT_WRITE',
  'CHOWN',
  'DAC_OVERRIDE',
  'FOWNER',
  'FSETID',
  'KILL',
  'MKNOD',
  'NET_BIND_SERVICE',
  'NET_ADMIN',
  'NET_RAW',
  'SETFCAP',
  'SETGID',
  'SETPCAP',
  'SETUID',
  'SYS_ADMIN',
  'SYS_CHROOT',
  'SYS_PTRACE',
];
local clusterScope = { 'tanka.dev/namespaced': 'false' };
local containerFields = ['containers', 'initContainers', 'ephemeralContainers'];

local containerValidation(field, dind, builder=false) =
  local isDind = (dind && field == 'initContainers') || (builder && field == 'containers');
  local daemon = if builder then 'buildkit' else 'dind';
  |||
    !has(object.spec.%(field)s) || object.spec.%(field)s.all(c,
      has(c.securityContext) &&
      has(c.securityContext.allowPrivilegeEscalation) && %(escalation)s &&
      has(c.securityContext.capabilities) &&
      has(c.securityContext.capabilities.drop) && 'ALL' in c.securityContext.capabilities.drop &&
      %(capabilities)s &&
      (!has(c.securityContext.seccompProfile) || c.securityContext.seccompProfile.type == 'RuntimeDefault')
    )
  ||| % {
    field: field,
    escalation: if isDind then '(c.name == "%s" || !c.securityContext.allowPrivilegeEscalation)' % daemon else '!c.securityContext.allowPrivilegeEscalation',
    capabilities: if isDind then
      '(!has(c.securityContext.capabilities.add) || (c.name == "%s" ? c.securityContext.capabilities.add.all(cap, cap in %s) : size(c.securityContext.capabilities.add) == 0))' % [daemon, std.manifestJson(dindCapabilities)]
    else '(!has(c.securityContext.capabilities.add) || size(c.securityContext.capabilities.add) == 0)',
  };

// KEDA Pod templates supply security settings directly; no mutation API or webhook is needed.
// Apply this stable guard before starting the replacement runner pools.
function(namespace, dind=false, name='forgejo-native-job-security', builder=false) {
  assert !builder || (namespace == 'forgejo-buildkit-canary' && !dind) : 'Persistent builder exception is limited to the isolated acceptance namespace',
  // Share the exact allowlist with the daemon template without rendering another resource
  dindCapabilities:: dindCapabilities,
  // Keep credential-free execution as the namespace default too
  nativeJobServiceAccount:
    serviceAccount.new('default')
    + serviceAccount.metadata.withNamespace(namespace)
    + serviceAccount.withAutomountServiceAccountToken(false),

  // Fail closed if a template or job requests incompatible settings.
  // Match every Pod in the namespace, not mutable job labels
  // DinD cannot use PSA baseline, so enforce its no-host/no-privileged constraints explicitly
  nativeJobSecurity:
    validatingAdmissionPolicy.new(name)
    + validatingAdmissionPolicy.metadata.withAnnotations(clusterScope)
    + validatingAdmissionPolicy.spec.withFailurePolicy('Fail')
    + validatingAdmissionPolicy.spec.matchConstraints.namespaceSelector.withMatchLabels({
      'kubernetes.io/metadata.name': namespace,
    })
    + validatingAdmissionPolicy.spec.matchConstraints.withResourceRules([{
      apiGroups: [''],
      apiVersions: ['v1'],
      operations: ['CREATE', 'UPDATE'],
      resources: ['pods', 'pods/ephemeralcontainers'],
      scope: 'Namespaced',
    }])
    + validatingAdmissionPolicy.spec.withValidations([
      {
        expression: 'has(object.spec.runtimeClassName) && object.spec.runtimeClassName == "%s"' % (if dind || builder then 'gvisor-dind' else 'gvisor'),
        message: 'Native Forgejo jobs must use the %s RuntimeClass.' % (if dind || builder then 'gvisor-dind' else 'gvisor'),
      },
      {
        expression: 'has(object.spec.automountServiceAccountToken) && !object.spec.automountServiceAccountToken',
        message: 'Native Forgejo jobs must disable service-account token automount.',
      },
      {
        expression: |||
          !has(object.spec.volumes) || object.spec.volumes.all(v,
            !has(v.projected) || v.projected.sources.all(s, !has(s.serviceAccountToken))
          )
        |||,
        message: 'Native Forgejo jobs must not project Kubernetes service-account tokens.',
      },
      {
        expression: |||
          has(object.spec.securityContext) && has(object.spec.securityContext.seccompProfile) &&
          object.spec.securityContext.seccompProfile.type == 'RuntimeDefault'
        |||,
        message: 'Native Forgejo jobs must use RuntimeDefault seccomp.',
      },
    ] + [
      {
        expression: containerValidation(field, dind, builder),
        message: if builder then '%s must drop ALL capabilities; only the buildkit ordinary container may add sandbox capabilities or allow privilege escalation.' % field
        else if dind then '%s must drop ALL capabilities; only the dind init sidecar may add sandbox capabilities or allow privilege escalation.' % field
        else '%s must disable privilege escalation, drop ALL capabilities without additions, and not override RuntimeDefault seccomp.' % field,
      }
      for field in containerFields
    ] + (if dind || builder then [
           {
             expression: |||
               (!has(object.spec.hostNetwork) || !object.spec.hostNetwork) &&
               (!has(object.spec.hostPID) || !object.spec.hostPID) &&
               (!has(object.spec.hostIPC) || !object.spec.hostIPC) &&
               (!has(object.spec.shareProcessNamespace) || !object.spec.shareProcessNamespace)
             |||,
             message: 'DinD Pods must not share host or container process namespaces.',
           },
           {
             expression: |||
               !has(object.spec.volumes) || object.spec.volumes.all(v,
                 has(v.emptyDir) || has(v.configMap) || has(v.secret) || has(v.downwardAPI) || has(v.projected)%(persistent)s
               )
             ||| % { persistent: if builder then ' || has(v.persistentVolumeClaim)' else '' },
             message: if builder then 'Builder Pods may use PVCs, ephemeral or configuration volumes, never host paths or devices.'
             else 'DinD Pods must use only ephemeral or configuration volumes, never host paths or devices.',
           },
         ] + [
           {
             expression: |||
               !has(object.spec.%(field)s) || object.spec.%(field)s.all(c,
                 (!has(c.securityContext.privileged) || !c.securityContext.privileged) &&
                 (!has(c.securityContext.procMount) || c.securityContext.procMount == 'Default') &&
                 (!has(c.ports) || c.ports.all(p, !has(p.hostPort) || p.hostPort == 0)) &&
                 (!has(c.volumeDevices) || size(c.volumeDevices) == 0)
               )
             ||| % { field: field },
             message: '%s must not be privileged or use host ports, unmasked proc or block devices.' % field,
           }
           for field in containerFields
         ] else [])),

  nativeJobSecurityBinding:
    validatingAdmissionPolicyBinding.new(name)
    + validatingAdmissionPolicyBinding.metadata.withAnnotations(clusterScope)
    + validatingAdmissionPolicyBinding.spec.withPolicyName(name)
    + validatingAdmissionPolicyBinding.spec.withValidationActions(['Deny']),
}
