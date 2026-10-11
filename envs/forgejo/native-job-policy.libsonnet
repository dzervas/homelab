local k = import 'k.libsonnet';

local validatingAdmissionPolicy = k.admissionregistration.v1.validatingAdmissionPolicy;
local validatingAdmissionPolicyBinding = k.admissionregistration.v1.validatingAdmissionPolicyBinding;
local serviceAccount = k.core.v1.serviceAccount;

local validationName = 'forgejo-native-job-security';
local clusterScope = { 'tanka.dev/namespaced': 'false' };
local containerFields = ['containers', 'initContainers', 'ephemeralContainers'];

local containerValidation(field) = |||
  !has(object.spec.%(field)s) || object.spec.%(field)s.all(c,
    has(c.securityContext) &&
    has(c.securityContext.allowPrivilegeEscalation) && !c.securityContext.allowPrivilegeEscalation &&
    has(c.securityContext.capabilities) &&
    has(c.securityContext.capabilities.drop) && 'ALL' in c.securityContext.capabilities.drop &&
    (!has(c.securityContext.capabilities.add) || size(c.securityContext.capabilities.add) == 0) &&
    (!has(c.securityContext.seccompProfile) || c.securityContext.seccompProfile.type == 'RuntimeDefault')
  )
||| % { field: field };

// KEDA Pod templates supply security settings directly; no mutation API or webhook is needed.
// Apply this stable guard before starting the replacement runner pools.
function(namespace) {
  // Keep credential-free execution as the namespace default too
  nativeJobServiceAccount:
    serviceAccount.new('default')
    + serviceAccount.metadata.withNamespace(namespace)
    + serviceAccount.withAutomountServiceAccountToken(false),

  // Fail closed if a template or job requests incompatible settings.
  // Match every Pod in the namespace, not mutable job labels. Baseline handles host access/privileged Pods.
  nativeJobSecurity:
    validatingAdmissionPolicy.new(validationName)
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
        expression: 'has(object.spec.runtimeClassName) && object.spec.runtimeClassName == "gvisor"',
        message: 'Native Forgejo jobs must use the gvisor RuntimeClass.',
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
        expression: containerValidation(field),
        message: '%s must disable privilege escalation, drop ALL capabilities without additions, and not override RuntimeDefault seccomp.' % field,
      }
      for field in containerFields
    ]),

  nativeJobSecurityBinding:
    validatingAdmissionPolicyBinding.new(validationName)
    + validatingAdmissionPolicyBinding.metadata.withAnnotations(clusterScope)
    + validatingAdmissionPolicyBinding.spec.withPolicyName(validationName)
    + validatingAdmissionPolicyBinding.spec.withValidationActions(['Deny']),
}
