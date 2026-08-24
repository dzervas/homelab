local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local k = import 'k.libsonnet';

local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local postgres = import './cluster.libsonnet';
local tenant = import './tenant.libsonnet';

local namespace = 'postgres';
local externalSecretsNamespace = 'external-secrets';
local tenantNamespaces = ['affine', 'n8n'];
local tenantSecretStoreName = 'postgres-tenants';

{
  sharedNamespace: k.core.v1.namespace.new(namespace),

  tenantSecretStore:
    clusterSecretStore.new(tenantSecretStoreName)
    // Only generated-password tenant namespaces may use this credential source.
    + clusterSecretStore.spec.withConditions([{ namespaces: ['affine'] }])
    + {
      spec+: {
        provider: {
          kubernetes: {
            remoteNamespace: namespace,
            server: {
              caProvider: {
                type: 'ConfigMap',
                name: 'kube-root-ca.crt',
                key: 'ca.crt',
                namespace: externalSecretsNamespace,
              },
            },
            auth: {
              serviceAccount: {
                name: tenantSecretStoreName,
                namespace: externalSecretsNamespace,
              },
            },
          },
        },
      },
    },

  tenantSecretStoreServiceAccount:
    k.core.v1.serviceAccount.new(tenantSecretStoreName)
    + k.core.v1.serviceAccount.metadata.withNamespace(externalSecretsNamespace),

  tenantSecretStoreRole:
    k.rbac.v1.role.new(tenantSecretStoreName)
    + k.rbac.v1.role.metadata.withNamespace(namespace)
    + k.rbac.v1.role.withRules([{
      apiGroups: [''],
      resources: ['secrets'],
      verbs: ['get', 'list', 'watch'],
    }]),

  tenantSecretStoreRoleBinding:
    k.rbac.v1.roleBinding.new(tenantSecretStoreName)
    + k.rbac.v1.roleBinding.metadata.withNamespace(namespace)
    + k.rbac.v1.roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + k.rbac.v1.roleBinding.roleRef.withKind('Role')
    + k.rbac.v1.roleBinding.roleRef.withName(tenantSecretStoreName)
    + k.rbac.v1.roleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: tenantSecretStoreName,
      namespace: externalSecretsNamespace,
    }]),

  // General-purpose cluster. Add one Database and role per application rather
  // than sharing the bootstrap `shared` role between tenants.
  sharedCluster: postgres.new('shared', namespace, '20Gi'),

  sharedTenantNetworkPolicy:
    k.networking.v1.networkPolicy.new('shared-tenants')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({ 'cnpg.io/cluster': 'shared' })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: std.map(function(tenantNamespace) {
        namespaceSelector: {
          matchLabels: { 'kubernetes.io/metadata.name': tenantNamespace },
        },
      }, tenantNamespaces),
      ports: [{ protocol: 'TCP', port: 5432 }],
    }]),

  tenants: {
    // Add a `postgres-password` field to the existing `n8n` 1Password item.
    // The application Secret will be named `n8n-postgres` in its namespace.
    n8n: tenant.new('n8n'),

    // Password generation is OnChange; restart Affine manually after rotation.
    affine: tenant.new('affine', generatePassword=true),
  },
}
