local k = import 'k.libsonnet';

local postgres = import './cluster.libsonnet';
local tenant = import './tenant.libsonnet';

local namespace = 'postgres';

{
  sharedNamespace: k.core.v1.namespace.new(namespace),

  // General-purpose cluster. Add one Database and role per application rather
  // than sharing the bootstrap `shared` role between tenants.
  sharedCluster: postgres.new('shared', namespace, '20Gi'),

  tenants: {
    // Add a `postgres-password` field to the existing `n8n` 1Password item.
    // The application Secret will be named `n8n-postgres` in its namespace.
    n8n: tenant.new('n8n'),
  },
}
