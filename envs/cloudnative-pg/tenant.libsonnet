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

local generatedCredentials(name, namespace, host) =
  externalSecret.new(name + '-postgres')
  + externalSecret.metadata.withNamespace(namespace)
  // Rotate only when this ExternalSecret is deliberately changed.
  + externalSecret.spec.withRefreshPolicy('OnChange')
  + externalSecret.spec.withDataFrom([{
    sourceRef: {
      generatorRef: {
        apiVersion: 'generators.external-secrets.io/v1alpha1',
        kind: 'ClusterGenerator',
        name: 'password',
      },
    },
  }])
  + externalSecret.spec.target.template.withType('kubernetes.io/basic-auth')
  + externalSecret.spec.target.template.metadata.withLabels({ 'cnpg.io/reload': 'true' })
  + externalSecret.spec.target.template.withData(connectionData(name, host));

local replicatedCredentials(name, namespace, sourceSecret, secretStore, host) =
  externalSecret.new(name + '-postgres')
  + externalSecret.metadata.withNamespace(namespace)
  + externalSecret.spec.withRefreshInterval('1m')
  + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
  + externalSecret.spec.secretStoreRef.withName(secretStore)
  + externalSecret.spec.withData([{
    secretKey: 'password',
    remoteRef: {
      key: sourceSecret,
      property: 'password',
    },
  }])
  + externalSecret.spec.target.template.withData(connectionData(name, host));

{
  new(
    name,
    appNamespace=name,
    credentialsKey=name,
    passwordProperty='postgres-password',
    clusterName='shared',
    clusterNamespace='postgres',
    generatePassword=false,
    replicationSecretStore='postgres-tenants'
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
        if generatePassword then generatedCredentials(name, clusterNamespace, host)
        else credentials(name, clusterNamespace, credentialsKey, passwordProperty, host, true),
    }
    + if appNamespace == clusterNamespace then {} else {
      applicationCredentials:
        if generatePassword then
          replicatedCredentials(name, appNamespace, secretName, replicationSecretStore, host)
        else credentials(name, appNamespace, credentialsKey, passwordProperty, host),
    },
}
