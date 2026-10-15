local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local k = import 'k.libsonnet';

local serviceAccount = k.core.v1.serviceAccount;
local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local networkPolicy = k.networking.v1.networkPolicy;
local networkPolicyIngressRule = k.networking.v1.networkPolicyIngressRule;
local ciliumClusterwideNetworkPolicy = cilium.cilium.v2.ciliumClusterwideNetworkPolicy;

{
  kubenav: {
    serviceAccount:
      serviceAccount.new('kubenav')
      + serviceAccount.metadata.withNamespace('kube-system'),
    clusterRole:
      clusterRole.new('kubenav')
      + clusterRole.withRules([
        {
          apiGroups: [''],
          resources: ['pods', 'pods/log', 'services', 'endpoints', 'namespaces', 'configmaps', 'events', 'nodes'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: [''],
          resources: ['pods/portforward'],
          verbs: ['create', 'delete'],
        },
        {
          apiGroups: [''],
          resources: ['pods'],
          verbs: ['delete'],
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments', 'replicasets', 'statefulsets', 'daemonsets'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['batch'],
          resources: ['jobs', 'cronjobs'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['metrics.k8s.io'],
          resources: ['pods', 'nodes'],
          verbs: ['get', 'list'],
        },
        {
          apiGroups: ['networking.k8s.io'],
          resources: ['ingresses'],
          verbs: ['get', 'list', 'watch'],
        },
        {
          apiGroups: ['apiextensions.k8s.io'],
          resources: ['customresourcedefinitions'],
          verbs: ['get', 'list', 'watch'],
        },
      ]),

    clusterRoleBinding:
      clusterRoleBinding.new('kubenav')
      + clusterRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
      + clusterRoleBinding.roleRef.withKind('ClusterRole')
      + clusterRoleBinding.roleRef.withName('kubenav')
      + clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: 'kubenav',
        namespace: 'kube-system',
      }]),
  },

  // Read-only access for local coding agents, using short-lived tokens minted with `kubectl create token`
  agentReadonly: {
    serviceAccount:
      serviceAccount.new('agent-readonly')
      + serviceAccount.metadata.withNamespace('kube-system'),
    clusterRole:
      clusterRole.new('agent-readonly')
      + clusterRole.withRules([
        // Secrets only exist in the core group, so only its resources are listed one by one
        // No pods/exec, pods/attach, pods/portforward, nodes/proxy or services/proxy: those are not reads
        {
          apiGroups: [''],
          resources: [
            'pods',
            'pods/log',
            'services',
            'endpoints',
            'namespaces',
            'nodes',
            'configmaps',
            'events',
            'persistentvolumes',
            'persistentvolumeclaims',
            'serviceaccounts',
            'replicationcontrollers',
            'podtemplates',
            'resourcequotas',
            'limitranges',
          ],
          verbs: ['get', 'list', 'watch'],
        },
        // RBAC has no deny and '*' would match the core group, so new CRD groups have to be added here
        // Drift check: kubectl get crd -o jsonpath='{range .items[*]}{.spec.group}{"\n"}{end}' | sort -u
        {
          apiGroups: [
            // Built-in
            'admissionregistration.k8s.io',
            'apiextensions.k8s.io',
            'apiregistration.k8s.io',
            'apps',
            'autoscaling',
            'batch',
            'certificates.k8s.io',
            'coordination.k8s.io',
            'discovery.k8s.io',
            'events.k8s.io',
            'flowcontrol.apiserver.k8s.io',
            'metrics.k8s.io',
            'networking.k8s.io',
            'node.k8s.io',
            'policy',
            'rbac.authorization.k8s.io',
            'resource.k8s.io',
            'scheduling.k8s.io',
            'storage.k8s.io',

            // CRDs
            'acme.cert-manager.io',
            'agents.hermeum.app',
            'cert-manager.io',
            'cilium.io',
            'collectors.grafana.com',
            'eventing.keda.sh',
            'external-secrets.io',
            'externaldns.k8s.io',
            'gateway.networking.k8s.io',
            'gateway.networking.x-k8s.io',
            'gemini.fairwinds.com',
            'generators.external-secrets.io',
            'helm.cattle.io',
            'hub.traefik.io',
            'k3s.cattle.io',
            'keda.sh',
            'longhorn.io',
            'monitoring.coreos.com',
            'monitoring.grafana.com',
            'postgresql.cnpg.io',
            'snapshot.storage.k8s.io',
            'traefik.io',
            'vpn.wireguard-operator.io',
          ],
          resources: ['*'],
          verbs: ['get', 'list', 'watch'],
        },
      ]),
    clusterRoleBinding:
      clusterRoleBinding.new('agent-readonly')
      + clusterRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
      + clusterRoleBinding.roleRef.withKind('ClusterRole')
      + clusterRoleBinding.roleRef.withName('agent-readonly')
      + clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: 'agent-readonly',
        namespace: 'kube-system',
      }]),
  },

  defaultDenyNP:
    ciliumClusterwideNetworkPolicy.new('default-ingress')
    // NS to affect
    + ciliumClusterwideNetworkPolicy.spec.endpointSelector.withMatchExpressions([
      ciliumClusterwideNetworkPolicy.spec.endpointSelector.matchExpressions.withKey('k8s:io.kubernetes.pod.namespace')
      + ciliumClusterwideNetworkPolicy.spec.endpointSelector.matchExpressions.withOperator('NotIn')
      + ciliumClusterwideNetworkPolicy.spec.endpointSelector.matchExpressions.withValues([
        'kube-system',
        'default',
        'ingress',
      ]),
    ])
    + ciliumClusterwideNetworkPolicy.spec.withIngress([
      ciliumClusterwideNetworkPolicy.spec.ingress.withFromEntities(['host', 'remote-node', 'ingress', 'world']),  // hostNetwork pods are NOT treated as ns pods
      ciliumClusterwideNetworkPolicy.spec.ingress.withFromEndpoints([
        {},  // Same namespace pods
        ciliumClusterwideNetworkPolicy.spec.ingress.fromEndpoints.withMatchExpressions([
          ciliumClusterwideNetworkPolicy.spec.ingress.fromEndpoints.matchExpressions.withKey('k8s:io.kubernetes.pod.namespace')
          + ciliumClusterwideNetworkPolicy.spec.ingress.fromEndpoints.matchExpressions.withOperator('In')
          + ciliumClusterwideNetworkPolicy.spec.ingress.fromEndpoints.matchExpressions.withValues([
            'kube-system',
            'ingress',
            'victoriametrics',
            'k8s-monitoring',
          ]),
        ]),
      ]),
    ]),

  defaultAllowNSNP: std.map(
    function(ns)
      networkPolicy.new('default-ns-allow')
      + networkPolicy.metadata.withNamespace(ns)
      + networkPolicy.spec.withPolicyTypes(['Ingress'])
      + networkPolicy.spec.withIngress([
        networkPolicyIngressRule.withFrom([{ podSelector: {} }]),
      ]),
    std.filter(function(ns) ns != 'kube-system' && ns != 'default' && ns != 'ingress', std.extVar('namespaces'))
  ),

  // TODO: Fine-grained control over the kube-system namespace
  // allowDNSNP:
  //   networkPolicy.new('allow-kube-system')
  //   + networkPolicy.metadata.withNamespace('kube-system')
  //   + networkPolicy.spec.withIngress([
  //     networkPolicyIngressRule.withFrom([{ namespaceSelector: {} }]),
  //   ]),

  // runsc is registered on every node by nixos/rke2/containerd.nix
  gvisor: {
    apiVersion: 'node.k8s.io/v1',
    kind: 'RuntimeClass',
    metadata: { name: 'gvisor', annotations: { 'tanka.dev/namespaced': 'false' } },
    handler: 'runsc',
    overhead: { podFixed: { cpu: '50m', memory: '64Mi' } },
    scheduling: { nodeSelector: { 'gvisor-runtime': 'running' } },
  },

  // DinD needs sandbox packet writes; ordinary gVisor workloads retain their existing handler
  // Native Kaniko/TLS DinD execution reported green on AMD64/ARM64; production acceptance remains unverified
  // TODO: Verify production admission, cache isolation, publication and live DinD teardown
  gvisorDind: {
    apiVersion: 'node.k8s.io/v1',
    kind: 'RuntimeClass',
    metadata: { name: 'gvisor-dind', annotations: { 'tanka.dev/namespaced': 'false' } },
    handler: 'runsc-dind',
    overhead: { podFixed: { cpu: '50m', memory: '64Mi' } },
    scheduling: { nodeSelector: { 'gvisor-dind-runtime': 'running' } },
  },

  shellAdmin: {
    serviceAccount:
      serviceAccount.new('shell-admin')
      + serviceAccount.metadata.withNamespace('kube-system'),
    clusterRoleBinding:
      clusterRoleBinding.new('shell-admin')
      + clusterRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
      + clusterRoleBinding.roleRef.withKind('ClusterRole')
      + clusterRoleBinding.roleRef.withName('cluster-admin')
      + clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: 'shell-admin',
        namespace: 'kube-system',
      }]),
  },
}
