local k = import 'k.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local clusterExternalSecret = externalSecrets.nogroup.v1.clusterExternalSecret;

local esNamespace = 'external-secrets';
local cmNamespace = 'cert-manager';

{
  // ClusterSecretStore that can read secrets from cert-manager namespace
  // Using raw object because the kubernetes provider has complex nested structure
  kubernetesStore:
    clusterSecretStore.new('kubernetes')
    + {
      spec+: {
        provider: {
          kubernetes: {
            remoteNamespace: cmNamespace,
            server: {
              caProvider: {
                type: 'ConfigMap',
                name: 'kube-root-ca.crt',
                key: 'ca.crt',
                namespace: esNamespace,
              },
            },
            auth: {
              serviceAccount: {
                name: 'external-secrets-client-ca',
                namespace: esNamespace,
              },
            },
          },
        },
      },
    },

  // ClusterRole for external-secrets to access cert-manager secrets
  clusterRole:
    k.rbac.v1.clusterRole.new('external-secrets-client-ca')
    + k.rbac.v1.clusterRole.withRules([
      {
        apiGroups: [''],
        verbs: ['list'],
        resources: ['secrets'],
      },
      {
        apiGroups: [''],
        verbs: ['get', 'watch'],
        resources: ['secrets'],
      },
      {
        apiGroups: [''],
        verbs: ['get'],
        resources: ['configmap'],
        resourceNames: ['kube-root-ca.crt'],
      },
    ]),

  // RoleBinding in cert-manager namespace
  roleBinding:
    k.rbac.v1.roleBinding.new('external-secrets-client-ca')
    + k.rbac.v1.roleBinding.metadata.withNamespace(cmNamespace)
    + k.rbac.v1.roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + k.rbac.v1.roleBinding.roleRef.withKind('ClusterRole')
    + k.rbac.v1.roleBinding.roleRef.withName('external-secrets-client-ca')
    + k.rbac.v1.roleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: 'external-secrets-client-ca',
      namespace: esNamespace,
    }]),

  // ServiceAccount for external-secrets
  serviceAccount:
    k.core.v1.serviceAccount.new('external-secrets-client-ca')
    + k.core.v1.serviceAccount.metadata.withNamespace(esNamespace),

  // ClusterExternalSecret to distribute client-ca to all namespaces
  globalClientCa:
    clusterExternalSecret.new('cm-global-client-ca')
    + clusterExternalSecret.spec.withExternalSecretName('client-ca')
    + clusterExternalSecret.spec.withNamespaceSelectors([
      { matchLabels: {} },  // Allow all namespaces
    ])
    + clusterExternalSecret.spec.externalSecretSpec.withRefreshInterval('1h')
    + clusterExternalSecret.spec.externalSecretSpec.secretStoreRef.withName('kubernetes')
    + clusterExternalSecret.spec.externalSecretSpec.secretStoreRef.withKind('ClusterSecretStore')
    + clusterExternalSecret.spec.externalSecretSpec.withData([{
      secretKey: 'ca.crt',
      remoteRef: {
        key: 'client-ca-certificate',
        property: 'ca.crt',
      },
    }]),
}
