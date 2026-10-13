local dind = import './dind.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local pod = k.core.v1.pod;
local role = k.rbac.v1.role;
local roleBinding = k.rbac.v1.roleBinding;
local serviceAccount = k.core.v1.serviceAccount;

local namespace = 'woodpecker';
local name = 'woodpecker-agent-native';
local arches = ['amd64', 'arm64'];
local labels(arch) = {
  // Reuse the existing server ingress and agent DNS/apiserver egress policies
  'app.kubernetes.io/name': 'agent',
  'app.kubernetes.io/instance': 'woodpecker',
  app: name,
  arch: arch,
};
{
  dindBootstrap:
    k.core.v1.configMap.new('woodpecker-dind', {
      'start-dind.sh': dind.tlsStartupScript,
      'daemon.sh': importstr 'dind.sh',
    })
    + k.core.v1.configMap.metadata.withNamespace(namespace),

  agentServiceAccount:
    serviceAccount.new(name)
    + serviceAccount.metadata.withNamespace('forgejo'),

  // Same namespaced backend permissions as the vendored chart; no worker access to the API
  agentRole:
    role.new(name)
    + role.metadata.withNamespace(namespace)
    + role.withRules([
      { apiGroups: [''], resources: ['persistentvolumeclaims', 'services', 'secrets'], verbs: ['create', 'delete'] },
      { apiGroups: [''], resources: ['pods'], verbs: ['watch', 'create', 'delete', 'get', 'list'] },
      { apiGroups: [''], resources: ['pods/log'], verbs: ['get'] },
    ]),
  agentRoleBinding:
    roleBinding.new(name)
    + roleBinding.metadata.withNamespace(namespace)
    + roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + roleBinding.roleRef.withKind('Role')
    + roleBinding.roleRef.withName(name)
    + roleBinding.withSubjects([{ kind: 'ServiceAccount', name: name, namespace: 'forgejo' }]),

  agents: {
    [arch]:
      deployment.new(name + '-' + arch)
      + deployment.metadata.withNamespace('forgejo')
      + deployment.spec.withReplicas(1)
      + deployment.spec.selector.withMatchLabels({ app: name, arch: arch })
      + {
        spec+: {
          template:
            pod.metadata.withLabels(labels(arch))
            + pod.spec.withServiceAccountName(name)
            + pod.spec.withNodeSelector({ 'kubernetes.io/arch': arch })
            + pod.spec.withContainers([
              container.new('agent', 'woodpeckerci/woodpecker-agent:v3.19.0')
              + container.withEnvFrom([{ secretRef: { name: 'woodpecker-agent-op' } }])
              + container.withEnvMap({
                WOODPECKER_SERVER: 'woodpecker-server.forgejo.svc:9000',
                WOODPECKER_BACKEND: 'kubernetes',
                WOODPECKER_BACKEND_K8S_NAMESPACE: namespace,
                WOODPECKER_BACKEND_K8S_NAMESPACE_PER_ORGANIZATION: 'false',
                WOODPECKER_BACKEND_K8S_STORAGE_CLASS: 'longhorn-throwaway',
                WOODPECKER_BACKEND_K8S_STORAGE_RWX: 'false',
                WOODPECKER_BACKEND_K8S_VOLUME_SIZE: '1Gi',
                WOODPECKER_BACKEND_K8S_POD_LABELS_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_POD_ANNOTATIONS_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_POD_NODE_SELECTOR_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_POD_AFFINITY_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_POD_TOLERATIONS_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_SECCTX_NONROOT: 'false',
                WOODPECKER_BACKEND_K8S_USER_NAMESPACES_OVERRIDE_SECCTX_NONROOT: 'false',
                WOODPECKER_BACKEND_K8S_RUNTIME_CLASS_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_SERVICE_ACCOUNT_NAME_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_ALLOW_NATIVE_SECRETS: 'false',
                WOODPECKER_AGENT_LABELS: 'platform=linux/' + arch,
                WOODPECKER_MAX_WORKFLOWS: '1',
                // Stock stateless registration unregisters on termination; no identity PVC required
                WOODPECKER_AGENT_CONFIG_FILE: '',
                WOODPECKER_HOSTNAME: name + '-' + arch,
                TZ: timezone,
              }),
            ]),
        },
      }
    for arch in arches
  },
}
