local jobPolicy = import '../forgejo/native-job-policy.libsonnet';
local agent = import './agent.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local k = import 'k.libsonnet';

local pvc = k.core.v1.persistentVolumeClaim;
local validatingPolicy = k.admissionregistration.v1.validatingAdmissionPolicy;
local validatingBinding = k.admissionregistration.v1.validatingAdmissionPolicyBinding;
local ciliumPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local namespace = 'woodpecker-canary';
local name = 'woodpecker-prototype';
local arches = ['amd64', 'arm64'];
local clusterScope = { 'tanka.dev/namespaced': 'false' };
local stepKey = 'woodpecker-ci.org/step';
local dindCapabilities = jobPolicy(namespace, dind=true).dindCapabilities;
// Docker's ordinary default set supports Kaniko filesystem operations inside gVisor
local defaultCapabilities = [cap for cap in dindCapabilities if !std.member(['NET_ADMIN', 'SYS_ADMIN', 'SYS_PTRACE'], cap)];
local canonical = 'has(object.metadata.labels) && "%s" in object.metadata.labels && object.metadata.labels["%s"].matches("^(clone|prototype-(build|warm|dind|docker)-(amd64|arm64))$")' % [stepKey, stepKey];
// Full name dzervas/homelab is normalized by backend/kubernetes/utils.go:toLabelValue
// Reserved server labels are trustworthy only with all backend label overrides disabled
local authorized = |||
  object.metadata.labels['woodpecker-ci.org/repo-name'] == 'homelab' &&
  object.metadata.labels['woodpecker-ci.org/repo-full-name'] == 'dzervas-homelab' &&
  object.metadata.labels['woodpecker-ci.org/event'] == 'manual' &&
  object.metadata.labels['woodpecker-ci.org/commit-branch'] == 'main'
|||;
local variables = [
  { name: 'step', expression: 'object.metadata.labels["%s"]' % stepKey },
  { name: 'arch', expression: 'string(object.spec.nodeSelector["kubernetes.io/arch"])' },
  { name: 'task', expression: 'object.metadata.labels["woodpecker-ci.org/task-uuid"]' },
  { name: 'clone', expression: 'variables.step == "clone"' },
  { name: 'dind', expression: 'variables.step.startsWith("prototype-dind-")' },
  { name: 'cache', expression: 'variables.step.startsWith("prototype-build-") || variables.step.startsWith("prototype-warm-")' },
  { name: 'cacheClaim', expression: '"woodpecker-prototype-cache-" + variables.arch' },
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

// Manual-only prototype with a dedicated agent and isolated worker namespace, no new controller
// Kubernetes v1.35 still defaults MutatingAdmissionPolicy=false; explicit feature gate AND
// Apply the staged nixos/rke2/config.nix server changes before creating these v1beta1 resources
// https://github.com/kubernetes/kubernetes/blob/v1.35.0/pkg/features/kube_features.go
// Dedicated agent disables backend label/annotation/runtimeClass/SA/nativeSecret overrides;
// leave repository trusted.volumes=false: CEL cannot look up PVC ownership/provenance
// RuntimeClass admission may precede MAP; inject its exact scheduling selector and overhead
// Clone uses the native agent arch; named step suffixes must agree. Required task affinity
// colocates clone, DinD and steps on one node (self-affinity bootstraps the first Pod)
// The backend workspace is wp_<random ULID>_<workflow ID>_default, unrelated to task UUID
// PSA privileged permits virtual SYS_ADMIN; CEL still forbids truly privileged Pods
// After the staged RKE2 change is rolled out to every server, verify API discovery:
// kubectl api-resources --api-group=admissionregistration.k8s.io | rg mutatingadmissionpolic
// Upgrade server/regular agents without touching Forgejo runners:
// tk apply envs/forgejo -t '^StatefulSet/woodpecker-(agent|server)$'
// Then install the namespace/guards BEFORE agents; keep repository trusted.volumes=false:
// tk apply envs/woodpecker-canary -t '^Namespace/woodpecker-canary$' -t '^(MutatingAdmissionPolicy|MutatingAdmissionPolicyBinding|ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding)/woodpecker-prototype$' -t '^ServiceAccount/default$'
// tk-ns apply envs/network
// kubectl get validatingadmissionpolicy woodpecker-prototype -o jsonpath='{.status.typeChecking}'
// Require empty VAP expressionWarnings before deploying agents; v1beta1 MAP has no status
// MAP CEL requires offline compilation and a server-side admission dry-run before manual execution
// tk apply envs/woodpecker-canary  (PVCs, network, bootstrap and agents only AFTER guard installation)
// Once .woodpecker/prototype.yaml is on main, manually run it twice: both arches must show the marked RUN cache hit and native TLS DinD PASS
// No PR execution or publication acceptance yet; this fixed homelab/main scope is not a dynamic cache allocator
// Cleanup: delete both forgejo/woodpecker-canary-agent-{amd64,arm64} Deployments, then delete namespace woodpecker-canary
// Also delete all four admission policies/bindings named woodpecker-prototype and traefik/woodpecker-prototype-clone CiliumNetworkPolicy
{
  workerNamespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({ 'pod-security.kubernetes.io/enforce': 'privileged' }),
  workerServiceAccount:
    k.core.v1.serviceAccount.new('default')
    + k.core.v1.serviceAccount.metadata.withNamespace(namespace)
    + k.core.v1.serviceAccount.withAutomountServiceAccountToken(false),

  cacheClaims: [
    pvc.new('woodpecker-prototype-cache-' + arch)
    + pvc.metadata.withNamespace(namespace)
    + pvc.spec.withAccessModes(['ReadWriteOncePod'])
    + pvc.spec.withStorageClassName('longhorn-throwaway')
    + pvc.spec.resources.withRequests({ storage: '2Gi' })
    for arch in arches
  ],

  // Longhorn CSI supports SINGLE_NODE_SINGLE_WRITER / ReadWriteOncePod upstream
  // https://github.com/longhorn/longhorn-manager/blob/v1.11.2/csi/controller_server.go
  // The vendored 1.12 chart has attacher 4.12, provisioner 5.3, resizer 2.1 (RWOP-capable)
  // Concurrent manual workflows wait for exclusive cache attachment; never downgrade to RWO
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
        { name: 'trusted-creator', expression: 'request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-canary-agent"' },
        { name: 'reserved-metadata', expression: authorized },
      ],
      variables: variables,
      mutations: [{
        patchType: 'JSONPatch',
        jsonPatch: {
          expression: |||
            [
              JSONPatch{op: 'add', path: '/spec/nodeSelector', value: {'kubernetes.io/arch': variables.arch, 'kubernetes.io/os': 'linux', 'gvisor-dind-runtime': 'running'}},
              JSONPatch{op: 'add', path: '/spec/runtimeClassName', value: 'gvisor-dind'},
              JSONPatch{op: 'add', path: '/spec/overhead', value: {'cpu': '50m', 'memory': '64Mi'}}, 
              JSONPatch{op: 'add', path: '/spec/affinity', value: Object.spec.affinity{
                podAffinity: Object.spec.affinity.podAffinity{requiredDuringSchedulingIgnoredDuringExecution: [
                  Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution{
                    labelSelector: Object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution.labelSelector{matchLabels: {'woodpecker-ci.org/task-uuid': variables.task}},
                    namespaces: ['woodpecker-canary'], topologyKey: 'kubernetes.io/hostname'
                  }
                ]}
              }}, 
              JSONPatch{op: 'add', path: '/spec/automountServiceAccountToken', value: false},
              JSONPatch{op: 'add', path: '/spec/enableServiceLinks', value: false},
              JSONPatch{op: 'add', path: '/spec/securityContext/seccompProfile', value: Object.spec.securityContext.seccompProfile{type: 'RuntimeDefault'}}, 
              %(security)s
            ] + (variables.cache ? [
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'prototype-cache', persistentVolumeClaim: Object.spec.volumes.persistentVolumeClaim{claimName: variables.cacheClaim}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'prototype-cache', mountPath: '/cache'}}
            ] : []) + (variables.dind ? [
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'prototype-docker', emptyDir: Object.spec.volumes.emptyDir{}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'prototype-docker', mountPath: '/var/lib/docker'}},
              JSONPatch{op: 'add', path: '/spec/volumes/-', value: Object.spec.volumes{name: 'prototype-startup', configMap: Object.spec.volumes.configMap{name: 'woodpecker-prototype-dind', items: [Object.spec.volumes.configMap.items{key: 'start-dind.sh', path: 'start-dind.sh'}]}}},
              JSONPatch{op: 'add', path: '/spec/containers/0/volumeMounts/-', value: Object.spec.containers.volumeMounts{name: 'prototype-startup', mountPath: '/prototype', readOnly: true}}
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
      validation(canonical + ' && (' + authorized + ')', 'Prototype steps are reserved for homelab manual/main workflows.'),
      validation('request.operation != "CREATE" || request.userInfo.username == "system:serviceaccount:forgejo:woodpecker-canary-agent"', 'Only the trusted Woodpecker agent may create prototype Pods.'),
      validation('variables.arch in ["amd64", "arm64"] && (variables.clone || variables.step.endsWith("-" + variables.arch)) && size(variables.task) > 0', 'Prototype step suffix must match the agent native architecture and carry the backend task UUID.'),
      validation('oldObject == null || object.metadata.labels == oldObject.metadata.labels', 'Prototype metadata must remain immutable.'),
      validation('object.spec.runtimeClassName == "gvisor-dind" && object.spec.nodeSelector["kubernetes.io/arch"] == variables.arch && object.spec.nodeSelector["gvisor-dind-runtime"] == "running" && !object.spec.automountServiceAccountToken', 'Prototype Pods require architecture placement, the gVisor runtime node selector and no service-account token.'),
      validation('has(object.spec.overhead) && size(object.spec.overhead) == 2 && object.spec.overhead["cpu"] == "50m" && object.spec.overhead["memory"] == "64Mi"', 'Prototype Pod overhead must match the gvisor-dind RuntimeClass.'),
      validation('!has(object.spec.serviceAccountName) || object.spec.serviceAccountName == "default"', 'Prototype Pods must not choose a privileged service account.'),
      validation('(!has(object.spec.hostNetwork) || !object.spec.hostNetwork) && (!has(object.spec.hostPID) || !object.spec.hostPID) && (!has(object.spec.hostIPC) || !object.spec.hostIPC) && (!has(object.spec.shareProcessNamespace) || !object.spec.shareProcessNamespace)', 'Prototype Pods must not share host or process namespaces.'),
      validation('!has(object.spec.imagePullSecrets) || size(object.spec.imagePullSecrets) == 0', 'Prototype Pods must not access Kubernetes image pull secrets.'),
      validation('size(object.spec.containers) == 1 && (!has(object.spec.ephemeralContainers) || size(object.spec.ephemeralContainers) == 0)', 'Prototype Pods must have exactly one step container and no ephemeral containers.'),
      validation(|||
        has(object.spec.affinity) && has(object.spec.affinity.podAffinity) &&
        size(object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution) == 1 &&
        object.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution.all(t,
          t.topologyKey == 'kubernetes.io/hostname' && t.namespaces == ['woodpecker-canary'] &&
          (!has(t.namespaceSelector)) && has(t.labelSelector) &&
          t.labelSelector.matchLabels['woodpecker-ci.org/task-uuid'] == variables.task && size(t.labelSelector.matchLabels) == 1 &&
          (!has(t.labelSelector.matchExpressions) || size(t.labelSelector.matchExpressions) == 0)
        )
      |||, 'All workflow Pods must be colocated on one node for their shared RWO workspace.'),
      validation('object.spec.securityContext.seccompProfile.type == "RuntimeDefault"', 'Prototype Pods must use RuntimeDefault seccomp.'),
      validation(|||
        object.spec.volumes.filter(v, has(v.persistentVolumeClaim) && v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$') && v.persistentVolumeClaim.claimName == v.name).size() == 1 &&
        object.spec.volumes.all(v,
          (has(v.persistentVolumeClaim) && v.persistentVolumeClaim.claimName == v.name && v.name.matches('^wp-[0-9a-hjkmnp-tv-z]{26}-[0-9]+-default$')) ||
          (variables.cache && v.name == 'prototype-cache' && has(v.persistentVolumeClaim) && v.persistentVolumeClaim.claimName == variables.cacheClaim) ||
          (variables.dind && v.name == 'prototype-docker' && has(v.emptyDir)) ||
          (variables.dind && v.name == 'prototype-startup' && has(v.configMap) && v.configMap.name == 'woodpecker-prototype-dind' &&
            v.configMap.items.size() == 1 && v.configMap.items[0].key == 'start-dind.sh' && v.configMap.items[0].path == 'start-dind.sh')
        ) && size(object.spec.volumes) == (variables.dind ? 3 : (variables.cache ? 2 : 1))
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
            ((!has(e.valueFrom.secretKeyRef) || (variables.clone && e.valueFrom.secretKeyRef.name == object.metadata.name + '-step-secret')) && !has(e.valueFrom.configMapKeyRef)))) &&
          (!has(c.volumeMounts) || c.volumeMounts.all(m,
            (!has(m.mountPropagation) || m.mountPropagation == 'None') &&
            (m.name != 'prototype-startup' || (m.mountPath == '/prototype' && has(m.readOnly) && m.readOnly))
          ))
        )
      ||| % {
        field: field,
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

  // Backend Service TCP 2376 uses same-namespace ingress and per-workflow mTLS
  // The separate Traefik rule below admits only the clone Pod to the Git HTTPS endpoint
  network:
    ciliumPolicy.new(name)
    + ciliumPolicy.metadata.withNamespace(namespace)
    + ciliumPolicy.spec.endpointSelector.withMatchExpressions([{
      key: stepKey,
      operator: 'In',
      values: ['clone'] + ['prototype-' + kind + '-' + arch for kind in ['build', 'warm', 'dind', 'docker'] for arch in arches],
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
        toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': namespace }, matchExpressions: [{ key: stepKey, operator: 'In', values: ['prototype-dind-' + arch for arch in arches] }] }],
        toPorts: [{ ports: [{ port: '2376', protocol: 'TCP' }] }],
      },
    ]),

  cloneIngress:
    ciliumPolicy.new('woodpecker-prototype-clone')
    + ciliumPolicy.metadata.withNamespace('traefik')
    + ciliumPolicy.spec.endpointSelector.withMatchLabels({ 'app.kubernetes.io/name': 'traefik' })
    + ciliumPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: {
        'k8s:io.kubernetes.pod.namespace': namespace,
        'k8s:woodpecker-ci.org/step': 'clone',
      } }],
      toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
    }]),
} + agent
