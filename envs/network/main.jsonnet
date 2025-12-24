local k = import 'k.libsonnet';
local serviceAccount = k.core.v1.serviceAccount;
local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

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
}
