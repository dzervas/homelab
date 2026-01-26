local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

local namespace = 'n8n';

{
  // n8n-runners deployment (external task runners)
  // Uses dockerService like the original TF module
  n8nRunners: dockerService.new('n8n-runners', 'ghcr.io/dzervas/n8n:latest', {
    namespace: namespace,
    type: 'Deployment',
    replicas: 0,
    command: ['/usr/local/bin/task-runner-launcher'],
    args: ['javascript'],
    ingressEnabled: false,

    env: {
      TZ: timezone,
      GENERIC_TIMEZONE: timezone,

      N8N_RUNNERS_TASK_BROKER_URI: 'http://n8n:5679',
      N8N_RUNNERS_MAX_CONCURRENCY: '5',
      N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT: '60',

      // TODO: Add mem limits
      // NODE_OPTIONS: '--max-old-space-size=<limit>',
    },

    op_envs: {
      N8N_RUNNERS_AUTH_TOKEN: 'password',  // Uses n8n-runner-token secret
    },
  }) {
    // Don't create a new namespace since we use n8n namespace
    namespace:: null,
    // The opsecret uses the wrong name, we use a generated password instead
    opsecret:: null,
  },
}
