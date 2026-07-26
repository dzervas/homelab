local cnpg = import 'cloudnative-pg-libsonnet/1.27.0/main.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';

local database = cnpg.postgresql.v1.database;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local connectionData(name, host) = {
  database: name,
  dbname: name,
  host: host,
  password: '{{ .password }}',
  port: '5432',
  uri: 'postgresql://%s:{{ .password | urlquery }}@%s:5432/%s' % [name, host, name],
  user: name,
  username: name,
};

local credentials(name, namespace, credentialsKey, passwordProperty, host, basicAuth=false) =
  externalSecret.new(name + '-postgres')
  + externalSecret.metadata.withNamespace(namespace)
  + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
  + externalSecret.spec.secretStoreRef.withName('1password')
  + externalSecret.spec.withData([{
    secretKey: 'password',
    remoteRef: {
      key: credentialsKey,
      property: passwordProperty,
    },
  }])
  + externalSecret.spec.target.template.withData(connectionData(name, host))
  + if basicAuth then
    externalSecret.spec.target.template.withType('kubernetes.io/basic-auth')
    + externalSecret.spec.target.template.metadata.withLabels({ 'cnpg.io/reload': 'true' })
  else {};

{
  new(
    name,
    appNamespace=name,
    credentialsKey=name,
    passwordProperty='postgres-password',
    clusterName='shared',
    clusterNamespace='postgres'
  )::
    local resourceName = clusterName + '-' + name;
    local secretName = name + '-postgres';
    local host = clusterName + '-rw.' + clusterNamespace + '.svc';
    {
      // DatabaseRole is newer than the latest generated CNPG Jsonnet library.
      role: {
        apiVersion: 'postgresql.cnpg.io/v1',
        kind: 'DatabaseRole',
        metadata: {
          name: resourceName,
          namespace: clusterNamespace,
        },
        spec: {
          cluster: { name: clusterName },
          name: name,
          login: true,
          passwordSecret: { name: secretName },
          databaseRoleReclaimPolicy: 'retain',
        },
      },

      database:
        database.new(resourceName)
        + database.metadata.withNamespace(clusterNamespace)
        + database.spec.cluster.withName(clusterName)
        + database.spec.withName(name)
        + database.spec.withOwner(name)
        + database.spec.withDatabaseReclaimPolicy('retain'),

      roleCredentials:
        credentials(name, clusterNamespace, credentialsKey, passwordProperty, host, true),
    }
    + if appNamespace == clusterNamespace then {} else {
      applicationCredentials:
        credentials(name, appNamespace, credentialsKey, passwordProperty, host),
    },
}
