local externalSecrets = import 'external-secrets.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local namespace = 'n8n';

{
  // n8n-runners deployment (external task runners)
  // Uses dockerService like the original TF module
  n8nRunners:
    lab.new('n8n-runners', 'n8nio/runners:stable')
    + lab.withNamespace(namespace)
    + lab.withCommand(['/usr/local/bin/task-runner-launcher'])
    + lab.withArgs(['javascript'])
    + lab.withSecretEnv({ N8N_RUNNERS_AUTH_TOKEN: { name: 'n8n-runners-auth-token', key: 'password' } })
    + lab.withPort({ port: 3000 })  // Shim since it's required
    + lab.withEnv({
      TZ: timezone,
      GENERIC_TIMEZONE: timezone,

      N8N_RUNNERS_TASK_BROKER_URI: 'http://n8n:5679',
      N8N_RUNNERS_MAX_CONCURRENCY: '5',
      N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT: '60',
    }),


  secretKey:
    externalSecret.new('n8n-runners-auth-token')
    + externalSecret.spec.target.template.withData({ password: '{{ .password }}' })
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
