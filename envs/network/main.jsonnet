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

}
