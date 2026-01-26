local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local namespace = 'n8n';

{
  // Note: n8n-op secret is created by dockerService in n8n.libsonnet via op_envs

  // Generated password for n8n runner auth token
  n8nRunnerToken:
    externalSecret.new('n8n-runner-token')
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }]),

  // Generated password for browserless token with templated output
  n8nBrowserlessToken:
    externalSecret.new('n8n-browserless-token')
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.target.template.withData({
      token: '{{ .password }}',
      credential_overwrite_data: std.manifestJsonMinified({
        browserlessApi: {
          url: 'http://n8n-browserless:3000',
          token: '{{ .password }}',
        },
      }),
      global_vars: std.manifestJsonMinified({
        browserless_host: 'n8n-browserless',
        browserless_port: '3000',
        browserless_token: '{{ .password }}',
        browserless_endpoint: 'ws://n8n-browserless:3000/?token={{ .password }}',
      }),
    })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }]),
}
