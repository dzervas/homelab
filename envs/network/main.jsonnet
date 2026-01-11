local calico = import 'calico-libsonnet/3.28/main.libsonnet';
local k = import 'k.libsonnet';

local serviceAccount = k.core.v1.serviceAccount;
local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local networkPolicy = k.networking.v1.networkPolicy;
local networkPolicyIngressRule = k.networking.v1.networkPolicyIngressRule;
local globalNetworkPolicy = calico.crd.v1.globalNetworkPolicy;

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

  defaultDenyNP: {
    apiVersion: 'projectcalico.org/v3',
    kind: 'GlobalNetworkPolicy',
    metadata: {
      name: 'default-ingress',
    },
    spec: {
      order: 1000,
      types: ['Ingress'],
      namespaceSelector: "projectcalico.org/name not in {'kube-system', 'default', 'ingress'}",
      ingress: [{
        action: 'Allow',
        source: {
          namespaceSelector: 'kubernetes.io/metadata.name in {"ingress","victoriametrics"}',
        },
      }],
    },
  },

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
