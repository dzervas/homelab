local dind = import './dind.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local k = import 'k.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;
local validatingPolicy = k.admissionregistration.v1.validatingAdmissionPolicy;
local validatingBinding = k.admissionregistration.v1.validatingAdmissionPolicyBinding;
local ciliumPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local namespace = 'woodpecker';
local name = 'woodpecker-jobs';
local arches = ['amd64', 'arm64'];
local directKanikoImages = ['martizih/kaniko:v1.28.6-debug', 'docker.io/martizih/kaniko:v1.28.6-debug'];
local kanikoPluginImages = ['woodpeckerci/plugin-kaniko:2.3.3', 'docker.io/woodpeckerci/plugin-kaniko:2.3.3'];
local clusterScope = { 'tanka.dev/namespaced': 'false' };
local stepKey = 'woodpecker-ci.org/step';
local dindCapabilities = dind.capabilities;
// Docker's ordinary default set supports Kaniko filesystem operations inside gVisor
local defaultCapabilities = [cap for cap in dindCapabilities if !std.member(['NET_ADMIN', 'SYS_ADMIN', 'SYS_PTRACE'], cap)];
// The server seals reserved labels; the dedicated agents disable every workflow override
// Numeric repo IDs avoid collisions introduced by backend toLabelValue normalization
local canonical = |||
  has(object.metadata.labels) &&
  ['woodpecker-ci.org/step', 'woodpecker-ci.org/repo-id', 'woodpecker-ci.org/event', 'woodpecker-ci.org/commit-branch', 'woodpecker-ci.org/task-uuid'].all(k, k in object.metadata.labels) &&
  object.metadata.labels['woodpecker-ci.org/repo-id'].matches('^[1-9][0-9]*$') &&
  object.metadata.labels['woodpecker-ci.org/task-uuid'].matches('^[a-zA-Z0-9_-]+$')
|||;
local variables = [
  { name: 'step', expression: 'object.metadata.labels["%s"]' % stepKey },
  { name: 'arch', expression: 'string(object.spec.nodeSelector["kubernetes.io/arch"])' },
  { name: 'task', expression: 'string(object.metadata.labels["woodpecker-ci.org/task-uuid"])' },
  // Image detection selects a bounded sandbox profile, never authority or secret eligibility
  // Direct WOODPECKER_CACHE or plugin PLUGIN_CACHE selects functionality, not tenancy/authority
  { name: 'dind', expression: 'object.spec.containers[0].image in %s' % std.manifestJson(['docker:' + dind.version + '-dind', 'docker.io/library/docker:' + dind.version + '-dind']) },
  {
    name: 'cache',
    expression: 'object.spec.containers[0].image in %(images)s && !("service" in object.metadata.labels) && object.metadata.name.startsWith("wp-") && !object.metadata.name.startsWith("wp-svc-") && has(object.spec.containers[0].env) && object.spec.containers[0].env.exists(e, e.name == (object.spec.containers[0].image in %(plugins)s ? "PLUGIN_CACHE" : "WOODPECKER_CACHE") && has(e.value) && e.value == "true")' % {
      images: std.manifestJson(directKanikoImages + kanikoPluginImages),
      plugins: std.manifestJson(kanikoPluginImages),
    },
  },
  { name: 'daemonName', expression: '"service" in object.metadata.labels ? string(object.metadata.labels["service"]) : string(object.spec.hostname)' },
  { name: 'cacheClaim', expression: '"woodpecker-cache-" + variables.arch' },
  { name: 'cachePath', expression: 'string(object.metadata.labels["woodpecker-ci.org/repo-id"]) + "/" + (object.metadata.labels["woodpecker-ci.org/event"] == "push" && object.metadata.labels["woodpecker-ci.org/commit-branch"] == "main" ? "main-push" : "untrusted") + "/" + variables.arch' },
];
local constraints(operations, resources) = {
  namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': namespace } },
  resourceRules: [{ apiGroups: [''], apiVersions: ['v1'], operations: operations, resources: resources, scope: 'Namespaced' }],
};
local validation(expression, message) = { expression: expression, message: message };
local security = |||
  JSONPatch{op: 'add', path: '/spec/containers/0/securityContext', value: Object.spec.containers.securityContext{
    privileged: false, allowPrivilegeEscalation: variables.dind,
    capabilities: Object.spec.containers.securityContext.capabilities{drop: ['ALL'], add: variables.dind ? %(dind)s : %(ordinary)s},
    seccompProfile: Object.spec.containers.securityContext.seccompProfile{type: 'RuntimeDefault'}
  }}
||| % { dind: std.manifestJson(dindCapabilities), ordinary: std.manifestJson(defaultCapabilities) };

// Staged rollout (operator only; do not apply before these gates):
// 1. Verify the existing nixos/rke2/config.nix MAP feature/API flags on EVERY server
//    No node upgrade/rebuild is required if those already-staged flags are active:
//    kubectl api-resources --api-group=admissionregistration.k8s.io | rg mutatingadmissionpolic
// 2. Pause incoming work and remove the old chart agent StatefulSet/SA/worker RoleBinding
//    BEFORE introducing fail-closed guards; retain server data and existing agent-op credentials
// 3. tk apply envs/forgejo -t '^Namespace/woodpecker$' -t '^ServiceAccount/default$'
//    tk-ns apply envs/network
//    tk apply envs/forgejo -t '^(MutatingAdmissionPolicy|MutatingAdmissionPolicyBinding|ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding)/woodpecker-jobs(-(secrets|resources))?$'
// 4. Require empty VAP status.typeChecking.expressionWarnings and actual apiserver MAP CEL
//    compilation/admission dry-run of positive AND hostile fixtures before worker deployment
// 5. Audit ALL repositories: trusted.volumes=false (no default server volumes); CEL cannot
//    look up backend workspace ownership. wp-ULID-workflow-default names alone are NOT ownership
//    Upstream clone uses inline user OAuth Netrc, not a scoped read-only job token: verify its
//    authority and PR exposure. Own step-secret refs only constrain K8s lookup, not secret provenance
//    Repository Woodpecker secrets/workflows, not this runner, govern publication eligibility
// 6. Install worker prerequisites without starting agents:
//    tk apply envs/forgejo -t '^(ConfigMap/woodpecker-dind|PersistentVolumeClaim/woodpecker-cache-(amd64|arm64)|ServiceAccount/woodpecker-agent-native|Role/woodpecker-agent-native|RoleBinding/woodpecker-agent-native|CiliumNetworkPolicy/woodpecker-jobs|CiliumNetworkPolicy/woodpecker-agent-apiserver-egress)$'
//    Ensure the existing server is v3.19.0+, old chart worker RBAC is absent, cache claims
//    report RWOP, credentials are ready (no value reads), then deploy agents LAST:
//    tk apply envs/forgejo -t '^Deployment/woodpecker-agent-native-(amd64|arm64)$'
//    Confirm each native agent registers with existing credentials before resuming incoming work
// 7. Live gates on BOTH arches: normal all-repo clone/build, cache cold/warm, concurrent
//    writers serialize, repo/trust isolation, PR secret eligibility, TLS DinD run/exec/teardown,
//    cancel cleanup and failed service detection. Never fall back to privileged/runc/RWO caches
// Shared per-arch cache capacity/operator cleanup is approved; PRs can consume shared capacity
// RWOP serializes every cache writer on that arch, including an accidentally detached writer
// v3.19 exposes no detached bit in Pod metadata: detached Kaniko is unsupported and can hold/queue
// writers until it terminates. Services are excluded; workflows must terminate cache consumers
// Kubelet safely creates missing subPath dirs
// (v1.35 kubelet_pods.go SafeMakeDir); no root mount/init provisioner/enrollment is needed
// DinD should be a detach:true ordinary step with failure:fail; it receives the shared workspace
// Services work only with backend workspace enabled; daemons without that volume fail closed
// Ordinary detached DNS uses backend hostname + per-task headless subdomain, not a Service label
// Bootstrap uses /opt/woodpecker-dind, separate from the upstream /woodpecker workspace
// RuntimeClass admission may precede MAP: inject exact scheduling selector AND overhead
{
  workerNamespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ 'pod-security.kubernetes.io/enforce': 'privileged' }),
  workerServiceAccount:
    k.core.v1.serviceAccount.new('default')
    + k.core.v1.serviceAccount.metadata.withNamespace(namespace)
    + k.core.v1.serviceAccount.withAutomountServiceAccountToken(false),

  cacheClaims: [
    pvc.new('woodpecker-cache-' + arch)
    + pvc.metadata.withNamespace(namespace)
    + pvc.spec.withAccessModes(['ReadWriteOncePod'])
    + pvc.spec.withStorageClassName('longhorn-throwaway')
    + pvc.spec.resources.withRequests({ storage: '20Gi' })
    for arch in arches
  ],

  // Longhorn CSI supports RWOP; never downgrade exclusive writers to RWO
  mutation: {
    apiVersion: 'admissionregistration.k8s.io/v1beta1',
    kind: 'MutatingAdmissionPolicy',
    metadata: { name: name, annotations: clusterScope },
    spec: {
      failurePolicy: 'Fail',
      reinvocationPolicy: 'Never',
      matchConstraints: constraints(['CREATE'], ['pods']),
      matchConditions: [
        { name: 'canonical-step', expression: canonical },
        { name: 'trusted-creator', expression: 'request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-agent-native"' },
      ],
      variables: variables,
      mutations: [{
        patchType: 'JSONPatch',
        jsonPatch: {
          expression: |||
            ((!has(object.spec.volumes) && (variables.cache || variables.dind)) ? [JSONPatch{op: 'add', path: '/spec/volumes', value: []}] : []) +
            ((!has(object.spec.containers[0].volumeMounts) && (variables.cache || variables.dind)) ? [JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts', value: []}] : []) +
            [
              JSONPatch{op: 'add', path: '/spec/nodeSelector', value: {'kubernetes.io/arch': variables.arch, 'kubernetes.io/os': 'linux', 'gvisor-dind-runtime': 'running'}},
              JSONPatch{op: 'add', path: '/spec/runtimeClassName', value: 'gvisor-dind'},
              JSONPatch{op: 'add', path: '/spec/overhead', value: {'cpu': '50m', 'memory': '64Mi'}}, 
              JSONPatch{op: 'add', path: '/spec/affinity', value: Object.spec.affinity{
                podAffinity: Object.spec.affinity.podAffinity{requiredDuringSchedulingIgnoredDuringExecution: [
                  Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution{
                    labelSelector: Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution.labelSelector{matchLabels: {'woodpecker-ci.org/task-uuid': variables.task}},
                    namespaces: ['woodpecker'], topologyKey: 'kubernetes.io/hostname'
                  }
                ]}
              }}, 
              JSONPatch{op: 'add', path: '/spec/automountServiceAccountToken', value: false},
              JSONPatch{op: 'add', path: '/spec/enableServiceLinks', value: false},
              JSONPatch{op: 'add', path: '/spec/securityContext', value: Object.spec.securityContext{fsGroup: 1000, seccompProfile: Object.spec.securityContext.seccompProfile{type: 'RuntimeDefault'}}}, 
              %(security)s
            ] + (variables.cache ? [
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'woodpecker-cache', persistentVolumeClaim: Object.spec.volumes.persistentVolumeClaim{claimName: variables.cacheClaim}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'woodpecker-cache', mountPath: '/cache', subPath: variables.cachePath}}
            ] : []) + (variables.dind ? [
              JSONPatch{op: 'add', path: '/spec/containers/0/command', value: ['/bin/sh', '/opt/woodpecker-dind/daemon.sh']},
              JSONPatch{op: 'add', path: '/spec/containers/0/args', value: []},
              JSONPatch{op: 'add', path: '/spec/containers/0/env', value: object.spec.containers[0].env.filter(e, !(e.name in ['DIND_SERVICE_NAME', 'DOCKER_TLS_CERTDIR', 'DOCKER_TLS_SAN'])) + [Object.spec.containers.env{name: 'DIND_SERVICE_NAME', value: variables.daemonName}]},
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'woodpecker-docker', emptyDir: Object.spec.volumes.emptyDir{}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'woodpecker-docker', mountPath: '/var/lib/docker'}},
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'woodpecker-startup', configMap: Object.spec.volumes.configMap{name: 'woodpecker-dind', items: [Object.spec.volumes.configMap.items{key: 'start-dind.sh', path: 'start-dind.sh'}, Object.spec.volumes.configMap.items{key: 'daemon.sh', path: 'daemon.sh'}]}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'woodpecker-startup', mountPath: '/opt/woodpecker-dind', readOnly: true}}
            ] : [])
          ||| % { security: security },
        },
      }],
    },
  },
  mutationBinding: {
    apiVersion: 'admissionregistration.k8s.io/v1beta1',
    kind: 'MutatingAdmissionPolicyBinding',
    metadata: { name: name, annotations: clusterScope },
    spec: { policyName: name },
  },

  guard:
    validatingPolicy.new(name)
    + validatingPolicy.metadata.withAnnotations(clusterScope)
    + validatingPolicy.spec.withFailurePolicy('Fail')
    + validatingPolicy.spec.matchConstraints.namespaceSelector.withMatchLabels({ 'kubernetes.io/metadata.name': namespace })
    + validatingPolicy.spec.matchConstraints.withResourceRules(constraints(['CREATE', 'UPDATE'], ['pods', 'pods/ephemeralcontainers']).resourceRules)
    // Every Pod in this isolated namespace fails closed, including spoofed/missing labels
    + validatingPolicy.spec.withVariables(variables)
    + validatingPolicy.spec.withValidations([
      validation(canonical, 'Server numeric repository ID, event, branch and task UUID are required.'),
      validation('request.operation != "CREATE" || request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-agent-native"', 'Only the trusted Woodpecker agent may create job Pods.'),
      validation('variables.arch in ["amd64", "arm64"] && size(variables.task) > 0', 'Jobs require a native architecture and server task UUID.'),
      validation('oldObject == null || (object.metadata.labels == oldObject.metadata.labels && ((!has(object.metadata.annotations) && !has(oldObject.metadata.annotations)) || (has(object.metadata.annotations) && has(oldObject.metadata.annotations) && object.metadata.annotations == oldObject.metadata.annotations)))', 'Woodpecker metadata must remain immutable.'),
      validation('object.spec.runtimeClassName == "gvisor-dind" && object.spec.nodeSelector["kubernetes.io/arch"] == variables.arch && object.spec.nodeSelector["gvisor-dind-runtime"] == "running" && object.spec.nodeSelector["kubernetes.io/os"] == "linux" && size(object.spec.nodeSelector) == 3 && !object.spec.automountServiceAccountToken', 'Woodpecker Pods require architecture placement, the gVisor runtime node selector and no service-account token.'),
      validation('has(object.spec.overhead) && size(object.spec.overhead) == 2 && object.spec.overhead["cpu"] == "50m" && object.spec.overhead["memory"] == "64Mi"', 'Woodpecker Pod overhead must match the gvisor-dind RuntimeClass.'),
      validation('!has(object.spec.serviceAccountName) || object.spec.serviceAccountName == "default"', 'Woodpecker Pods must not choose a privileged service account.'),
      validation('(!has(object.spec.hostNetwork) || !object.spec.hostNetwork) && (!has(object.spec.hostPID) || !object.spec.hostPID) && (!has(object.spec.hostIPC) || !object.spec.hostIPC) && (!has(object.spec.shareProcessNamespace) || !object.spec.shareProcessNamespace)', 'Woodpecker Pods must not share host or process namespaces.'),
      // v3.19 secrets.go registrySecretName uses wp-UUID even for service Pods
      validation('!has(object.spec.imagePullSecrets) || (size(object.spec.imagePullSecrets) <= 1 && object.spec.imagePullSecrets.all(s, s.name == ("service" in object.metadata.labels ? "wp-" + object.metadata.name.split("-")[2] : object.metadata.name)))', 'Only the backend-generated own-step registry credential may pull private images.'),
      validation('(request.operation != "CREATE" || !has(object.spec.nodeName) || object.spec.nodeName == "") && (!has(object.spec.tolerations) || object.spec.tolerations.all(t, t.key in ["node.kubernetes.io/not-ready", "node.kubernetes.io/unreachable"] && t.effect == "NoExecute" && t.operator == "Exists" && t.tolerationSeconds == 300))', 'Jobs cannot bypass scheduling or select arbitrary tolerations.'),
      validation('!has(object.spec.securityContext.sysctls) || size(object.spec.securityContext.sysctls) == 0', 'Jobs must not request sandbox sysctl overrides.'),
      validation('!has(object.spec.schedulerName) || object.spec.schedulerName == "default-scheduler"', 'Jobs must use the default scheduler for enforced placement and affinity.'),
      validation('size(object.spec.containers) == 1 && (!has(object.spec.ephemeralContainers) || size(object.spec.ephemeralContainers) == 0)', 'Woodpecker Pods must have exactly one step container and no ephemeral containers.'),
      validation(|||
        has(object.spec.affinity) && has(object.spec.affinity.podAffinity) &&
        size(object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution) == 1 &&
        object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution.all(t,
          t.topologyKey == 'kubernetes.io/hostname' && t.namespaces == ['woodpecker'] &&
          (!has(t.namespaceSelector)) && has(t.labelSelector) &&
          t.labelSelector.matchLabels['woodpecker-ci.org/task-uuid'] == variables.task && size(t.labelSelector.matchLabels) == 1 &&
          (!has(t.labelSelector.matchExpressions) || size(t.labelSelector.matchExpressions) == 0)
        )
      |||, 'All workflow Pods must be colocated on one node for their shared RWO workspace.'),
      validation('object.spec.securityContext.seccompProfile.type == "RuntimeDefault"', 'Woodpecker Pods must use RuntimeDefault seccomp.'),
      validation('!variables.cache || object.spec.containers[0].volumeMounts.filter(m, m.name == "woodpecker-cache").size() == 1', 'Kaniko must have exactly one mandatory tenant cache mount.'),
      validation('!variables.dind || object.spec.volumes.filter(v, v.name.matches("^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$")).size() == 1', 'DinD requires the backend workspace for task-private TLS certificates.'),
      validation('!variables.dind || (object.spec.containers[0].command == ["/bin/sh", "/opt/woodpecker-dind/daemon.sh"] && (!has(object.spec.containers[0].args) || size(object.spec.containers[0].args) == 0) && object.spec.containers[0].env.filter(e, e.name == "DIND_SERVICE_NAME" && has(e.value) && e.value == variables.daemonName).size() == 1)', 'DinD must exec the generic bootstrap with the backend service name.'),
      validation('!variables.dind || (object.spec.containers[0].volumeMounts.filter(m, m.name == "woodpecker-docker").size() == 1 && object.spec.containers[0].volumeMounts.filter(m, m.name == "woodpecker-startup").size() == 1)', 'DinD must have disposable disk state and read-only bootstrap.'),
      validation(|||
        (object.spec.volumes.filter(v, has(v.persistentVolumeClaim) && v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && v.persistentVolumeClaim.claimName == v.name).size() == ('service' in object.metadata.labels ? 0 : 1) || object.spec.volumes.filter(v, has(v.persistentVolumeClaim) && v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && v.persistentVolumeClaim.claimName == v.name).size() == 1) &&
        object.spec.volumes.all(v,
          (has(v.persistentVolumeClaim) && v.persistentVolumeClaim.claimName == v.name && v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$')) ||
          (variables.cache && v.name == 'woodpecker-cache' && has(v.persistentVolumeClaim) && v.persistentVolumeClaim.claimName == variables.cacheClaim) ||
          (variables.dind && v.name == 'woodpecker-docker' && has(v.emptyDir) && (!has(v.emptyDir.medium) || v.emptyDir.medium == '')) ||
          (variables.dind && v.name == 'woodpecker-startup' && has(v.configMap) && v.configMap.name == 'woodpecker-dind' &&
            v.configMap.items.size() == 2 && v.configMap.items[0].key == 'start-dind.sh' && v.configMap.items[0].path == 'start-dind.sh' && v.configMap.items[1].key == 'daemon.sh' && v.configMap.items[1].path == 'daemon.sh')
        ) && size(object.spec.volumes) == object.spec.volumes.filter(v, v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$')).size() + (variables.dind ? 2 : (variables.cache ? 1 : 0))
      |||, 'Only the backend workspace and the selected cache PVC or disposable DinD volume are allowed.'),
    ] + [
      validation(|||
        !has(object.spec.%(field)s) || object.spec.%(field)s.all(c,
          has(c.securityContext) && (!has(c.securityContext.privileged) || !c.securityContext.privileged) &&
          (!has(c.securityContext.procMount) || c.securityContext.procMount == 'Default') &&
          has(c.securityContext.allowPrivilegeEscalation) && (!c.securityContext.allowPrivilegeEscalation || %(dind)s) &&
          has(c.securityContext.capabilities) && 'ALL' in c.securityContext.capabilities.drop &&
          (!has(c.securityContext.capabilities.add) || c.securityContext.capabilities.add.all(cap, cap in (%(dind)s ? %(caps)s : %(ordinary)s))) &&
          (!has(c.securityContext.seccompProfile) || c.securityContext.seccompProfile.type == 'RuntimeDefault') &&
          (!has(c.ports) || c.ports.all(p, !has(p.hostPort) || p.hostPort == 0)) &&
          (!has(c.volumeDevices) || size(c.volumeDevices) == 0) &&
          (!has(c.envFrom) || size(c.envFrom) == 0) &&
          (!has(c.env) || c.env.all(e, !has(e.valueFrom) ||
            ((!has(e.valueFrom.secretKeyRef) || (e.valueFrom.secretKeyRef.name == object.metadata.name + '-step-secret' && e.valueFrom.secretKeyRef.key == e.name)) && !has(e.valueFrom.configMapKeyRef)))) &&
          (!has(c.volumeMounts) || (c.volumeMounts.all(m, c.volumeMounts.filter(other, other.mountPath == m.mountPath).size() == 1) && c.volumeMounts.all(m,
            (!has(m.mountPropagation) || m.mountPropagation == 'None') &&
            (!has(m.subPathExpr) || m.subPathExpr == '') &&
            (%(main)s ? (
              (m.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && (!has(m.subPath) || m.subPath == '')) ||
              (variables.cache && m.name == 'woodpecker-cache' && m.mountPath == '/cache' && has(m.subPath) && m.subPath == variables.cachePath && !has(m.subPathExpr) && (!has(m.readOnly) || !m.readOnly)) ||
              (variables.dind && m.name == 'woodpecker-docker' && m.mountPath == '/var/lib/docker' && (!has(m.subPath) || m.subPath == '')) ||
              (variables.dind && m.name == 'woodpecker-startup' && m.mountPath == '/opt/woodpecker-dind' && has(m.readOnly) && m.readOnly && (!has(m.subPath) || m.subPath == '') && !has(m.subPathExpr))
            ) : (m.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && (!has(m.subPath) || m.subPath == '')))

          )))
        )
      ||| % {
        field: field,
        main: if field == 'containers' then 'true' else 'false',
        dind: if field == 'containers' then 'variables.dind' else 'false',
        caps: std.manifestJson(dindCapabilities),
        ordinary: if field == 'containers' then std.manifestJson(defaultCapabilities) else '[]',
      }, 'Containers must not request host access, secrets, privilege or capabilities beyond the sandbox allowlist.')
      for field in ['containers', 'initContainers', 'ephemeralContainers']
    ]),
  guardBinding:
    validatingBinding.new(name)
    + validatingBinding.metadata.withAnnotations(clusterScope)
    + validatingBinding.spec.withPolicyName(name)
    + validatingBinding.spec.withValidationActions(['Deny']),

  // Agent CREATE/DELETE cannot overwrite/bootstrap arbitrary secrets; no secret values examined
  secretGuard:
    validatingPolicy.new(name + '-secrets')
    + validatingPolicy.metadata.withAnnotations(clusterScope)
    + validatingPolicy.spec.withFailurePolicy('Fail')
    + { spec+: { matchConstraints: constraints(['CREATE', 'UPDATE', 'DELETE'], ['secrets']) } }
    + validatingPolicy.spec.withVariables([{ name: 'target', expression: 'request.operation == "DELETE" ? oldObject : object' }])
    + validatingPolicy.spec.withValidations([
      validation('request.operation == "DELETE" || (request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-agent-native" && request.operation == "CREATE")', 'Only trusted agents may create generated job secrets; updates are forbidden. RBAC-authorized deletion permits cleanup.'),
      validation("(variables.target.type == 'Opaque' && variables.target.metadata.name.matches('^wp-(svc-)?[a-z0-9]{26}(-[a-z0-9-]+)?-step-secret$')) || (variables.target.type == 'kubernetes.io/dockerconfigjson' && variables.target.metadata.name.matches('^wp-[a-z0-9]{26}$'))", 'Only backend step-secret and own-step image-pull secret names/types are allowed.'),
    ]),
  secretGuardBinding:
    validatingBinding.new(name + '-secrets')
    + validatingBinding.metadata.withAnnotations(clusterScope)
    + validatingBinding.spec.withPolicyName(name + '-secrets')
    + validatingBinding.spec.withValidationActions(['Deny']),

  // RBAC has namespace-wide backend CREATE/DELETE, so it must not delete shared cache claims
  resourceGuard:
    validatingPolicy.new(name + '-resources')
    + validatingPolicy.metadata.withAnnotations(clusterScope)
    + validatingPolicy.spec.withFailurePolicy('Fail')
    + { spec+: { matchConstraints: constraints(['CREATE', 'UPDATE', 'DELETE'], ['persistentvolumeclaims', 'services']) } }
    + validatingPolicy.spec.withVariables([
      { name: 'target', expression: 'request.operation == "DELETE" ? oldObject : object' },
      { name: 'agent', expression: 'request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-agent-native"' },
      { name: 'cache', expression: 'request.resource.resource == "persistentvolumeclaims" && variables.target.metadata.name in ["woodpecker-cache-amd64", "woodpecker-cache-arm64"]' },
    ])
    + validatingPolicy.spec.withValidations([
      // Binding controllers update workspace PVCs; RBAC-authorized operators/GC must also be able to clean up
      validation('variables.cache ? !variables.agent : (request.operation == "CREATE" ? variables.agent : (request.operation == "DELETE" || !variables.agent))', 'Only trusted agents may create backend resources; agent updates are forbidden and shared cache claims are operator-owned.'),
      validation("request.resource.resource != 'persistentvolumeclaims' || variables.cache || request.operation != 'CREATE' || !has(variables.target.spec.volumeName) || variables.target.spec.volumeName == ''", 'New workspace claims must not select an existing volume; controllers bind them after creation.'),
      validation("request.resource.resource != 'persistentvolumeclaims' || (variables.cache ? (variables.target.spec.accessModes == ['ReadWriteOncePod'] && variables.target.spec.storageClassName == 'longhorn-throwaway') : (variables.target.metadata.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && variables.target.spec.accessModes == ['ReadWriteOnce'] && variables.target.spec.storageClassName == 'longhorn-throwaway' && !has(variables.target.spec.dataSource) && !has(variables.target.spec.dataSourceRef) && !has(variables.target.spec.selector)))", 'Backend workspaces must be disposable RWO claims, never a selected/copied existing volume; caches require RWOP.'),
      validation("request.resource.resource != 'services' || variables.target.metadata.name.matches('^wp-(hsvc|svc)-[a-z0-9-]+$')", 'Only backend-generated workflow Service names may be created.'),
      validation("request.resource.resource != 'services' || ((!has(variables.target.spec.type) || variables.target.spec.type == 'ClusterIP') && (!has(variables.target.spec.externalIPs) || size(variables.target.spec.externalIPs) == 0) && (!has(variables.target.spec.externalName) || variables.target.spec.externalName == '') && (!has(variables.target.spec.loadBalancerIP) || variables.target.spec.loadBalancerIP == '') && (!has(variables.target.spec.ports) || variables.target.spec.ports.all(p, !has(p.nodePort) || p.nodePort == 0)))", 'Workflow Services must remain internal, without NodePort, external addresses or load balancers.'),
    ]),
  resourceGuardBinding:
    validatingBinding.new(name + '-resources')
    + validatingBinding.metadata.withAnnotations(clusterScope)
    + validatingBinding.spec.withPolicyName(name + '-resources')
    + validatingBinding.spec.withValidationActions(['Deny']),

  // Upstream Services select task UUID (headless) or unique service UUID, not step names
  // Static Cilium rules cannot compare source/destination task labels; per-workflow mTLS
  // authenticates 2376 across this namespace. Other workflow services must authenticate too
  // Same-worker-namespace IPC supports ordinary Redis/Postgres/etc; cross-namespace egress stays closed
  network:
    ciliumPolicy.new(name)
    + ciliumPolicy.metadata.withNamespace(namespace)
    + ciliumPolicy.spec.endpointSelector.withMatchLabels({})
    + ciliumPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace } }],
    }])
    + ciliumPolicy.spec.withEgress([
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
        toPorts: [{ ports: [{ port: '53', protocol: 'ANY' }], rules: { dns: [{ matchPattern: '*' }] } }],
      },
      { toEntities: ['world'], toPorts: [{ ports: [{ port: '443', protocol: 'TCP' }] }] },
      {
        toEndpoints: [{ matchLabels: {
          'k8s:io.kubernetes.pod.namespace': 'traefik',
          'k8s:app.kubernetes.io/instance': 'traefik-traefik',
          'k8s:app.kubernetes.io/name': 'traefik',
        } }],
        toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
      },
      {
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace } }],
      },
    ]),

  traefikIngress:
    ciliumPolicy.new('woodpecker-jobs')
    + ciliumPolicy.metadata.withNamespace('traefik')
    + ciliumPolicy.spec.endpointSelector.withMatchLabels({ 'app.kubernetes.io/name': 'traefik' })
    + ciliumPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace } }],
      toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
    }]),
}
