local externalSecrets = import 'external-secrets.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  new(name)::
    externalSecret.new(name + '-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: name } }]),
}
