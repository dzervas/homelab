local dockerService = import 'docker-service.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local statefulset = k.apps.v1.statefulSet;

local namespace = 'n8n';
local domain = 'dzerv.art';

{
  // Main n8n statefulset
  n8n: dockerService.new('n8n', 'ghcr.io/dzervas/n8n:latest', {
    fqdn: 'auto.' + domain,
    ports: [5678],
    labels: {},
    pvs: {
      '/home/node/.n8n': {
        name: 'data',
        size: '10Gi',
      },
      '/home/node/backups': {
        name: 'backups',
        size: '10Gi',
      },
    },
    ingressAnnotations:
      ingress.mtlsAnnotations(namespace)
      + { 'nginx.ingress.kubernetes.io/proxy-body-size': '16m' },

    env: {
      TZ: timezone,
      GENERIC_TIMEZONE: timezone,

      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS: 'true',
      N8N_DEFAULT_BINARY_DATA_MODE: 'filesystem',

      N8N_EDITOR_BASE_URL: 'https://auto.' + domain,
      WEBHOOK_URL: 'https://hook.' + domain,
      N8N_PROXY_HOPS: '1',
      N8N_PORT: '5678',

      N8N_RUNNERS_ENABLED: 'true',
      N8N_RUNNERS_MODE: 'internal',
      N8N_RUNNERS_BROKER_LISTEN_ADDRESS: '0.0.0.0',

      EXECUTIONS_TIMEOUT: '600',
      EXECUTIONS_DATA_PRUNE: 'true',
      EXECUTIONS_DATA_MAX_AGE: '168',
      EXECUTIONS_DATA_PRUNE_MAX_COUNT: '50000',

      N8N_METRICS: 'true',
      QUEUE_HEALTH_CHECK_ACTIVE: 'true',

      // TODO: Requires https
      // N8N_EXTERNAL_STORAGE_S3_HOST          : "rclone.rclone.svc.cluster.local:8080"
      // N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME   : "n8n"
      // N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION : "auto"
      // N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY    : random_password.rclone_access_key.result
      // N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET : random_password.rclone_secret_key.result
      // N8N_AVAILABLE_BINARY_DATA_MODES       : "filesystem,s3"
      // N8N_DEFAULT_BINARY_DATA_MODE          : "s3"

      // Disable diagnostics (https://docs.n8n.io/hosting/configuration/configuration-examples/isolation/)
      EXTERNAL_FRONTEND_HOOKS_URLS: '',
      N8N_DIAGNOSTICS_ENABLED: 'false',
      N8N_DIAGNOSTICS_CONFIG_FRONTEND: '',
      N8N_DIAGNOSTICS_CONFIG_BACKEND: '',

      N8N_PUBLIC_API_DISABLED: 'false',

      DB_SQLITE_POOL_SIZE: '10',
      DB_SQLITE_VACUUM_ON_STARTUP: 'true',  // Makes startup take years
    },

    op_envs: {
      N8N_ENCRYPTION_KEY: 'encryption-key',
      // N8N_RUNNERS_AUTH_TOKEN: 'password',  // n8n-runner
      // CREDENTIAL_OVERWRITE_DATA: 'credential_overwrite_data',  // browserless
    },
  }) + {
    workload+:
      statefulset.spec.template.metadata.withLabelsMixin({
        'magicentry.rs/enable': 'true',
        'ai/enable': 'true',
      }),
  },
}
