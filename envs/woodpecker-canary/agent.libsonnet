local dind = import '../forgejo/dind.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local pod = k.core.v1.pod;
local role = k.rbac.v1.role;
local roleBinding = k.rbac.v1.roleBinding;
local serviceAccount = k.core.v1.serviceAccount;

local namespace = 'woodpecker-canary';
local name = 'woodpecker-canary-agent';
local arches = ['amd64', 'arm64'];
local labels(arch) = {
  // Reuse the existing server ingress and agent DNS/apiserver egress policies
  'app.kubernetes.io/name': 'agent',
  'app.kubernetes.io/instance': 'woodpecker',
  app: name,
  arch: arch,
};
local startupHeader = 'exec dockerd-entrypoint.sh dockerd \\\n  --host="$DOCKER_HOST" --group=1000 \\\n';
// Let the stock entrypoint generate verified TCP TLS; leave every existing Unix-socket caller byte-identical
local tlsStartup = std.strReplace(dind.startupScript, startupHeader, 'exec dockerd-entrypoint.sh \\\n  --group=1000 \\\n');

assert std.length(std.findSubstr(startupHeader, dind.startupScript)) == 1 : 'DinD bootstrap header changed; review TLS adaptation';
{
  dindBootstrap:
    k.core.v1.configMap.new('woodpecker-prototype-dind', { 'start-dind.sh': tlsStartup })
    + k.core.v1.configMap.metadata.withNamespace(namespace),

  agentServiceAccount:
    serviceAccount.new(name)
    + serviceAccount.metadata.withNamespace('forgejo'),

  // Same namespaced backend permissions as the vendored chart, never the production worker namespace
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
                WOODPECKER_BACKEND_K8S_RUNTIME_CLASS_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_SERVICE_ACCOUNT_NAME_ALLOW_FROM_STEP: 'false',
                WOODPECKER_BACKEND_K8S_ALLOW_NATIVE_SECRETS: 'false',
                // Reserved labels are server-authored; the ordinary label only keeps existing agents out
                WOODPECKER_AGENT_LABELS: std.join(',', [
                  '!woodpecker-ci.org/repo-name=homelab',
                  '!woodpecker-ci.org/repo-full-name=dzervas/homelab',
                  '!woodpecker-ci.org/event=manual',
                  '!woodpecker-ci.org/commit-branch=main',
                  '!woodpecker-prototype=true',
                  'platform=linux/' + arch,
                ]),
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
