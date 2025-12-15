local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local gemini = import 'helpers/gemini.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'plane';
local domain = 'projects.dzerv.art';
local prime_server = 'http://plane-prime:8000';

// Normalize Helm-rendered Jobs: detect names ending in "-YYYYMMDD-HHMMSS",
// strip the timestamp to make names/keys deterministic, and keep metadata in sync.
local normalizeJobNames(obj) =
  local isDigits(s) = std.foldl(function(acc, c) acc && c >= '0' && c <= '9', std.stringChars(s), true);
  local rebuild = function(acc, k)
    local v = obj[k] { spec+: { template+: { metadata+: { annotations+: { timestamp: null } } } } };
    if std.isObject(v) && v.kind == 'Job' && std.objectHas(v, 'metadata') && std.objectHas(v.metadata, 'name') then
      local parts = std.split(v.metadata.name, '-');
      local n = std.length(parts);
      local hasDateSuffix =
        n >= 2 &&
        std.length(parts[n - 2]) == 8 && isDigits(parts[n - 2]) &&
        std.length(parts[n - 1]) == 6 && isDigits(parts[n - 1]);
      local baseName = if hasDateSuffix then std.join('-', parts[0:n - 2]) else v.metadata.name;
      local newKey = 'job_' + baseName;
      acc {
        [newKey]: v {
          metadata+: { name: baseName },
        },
      }
    else
      acc { [k]: v };
  std.foldl(rebuild, std.objectFields(obj), {});

{
  // NOTE: Creates the namespace
  planePrime: dockerService.new('plane-prime', 'ghcr.io/dzervas/plane-prime:latest', {
    namespace: namespace,
    port: 8000,
  }),
  // Normalize job names so they stay stable across renders
  plane: std.prune(normalizeJobNames(
    helm.template('plane', '../../charts/plane-enterprise', {
      namespace: namespace,
      values: {
        // TODO: Add timezone
        license: {
          licenseDomain: domain,
          licenseServer: prime_server,
        },
        ingress: {
          enabled: true,
          ingressClass: 'nginx',
          ingress_annotations: {
            'nginx.ingress.kubernetes.io/proxy-body-size': '5m',
            // Required to get mobile app to work
            'nginx.ingress.kubernetes.io/auth-snippet': 'if ($request_uri ~ "(/auth/get-csrf-token/|/auth/mobile/(token-check|session-token)/)") { return 200; }',
          } + ingress.oidcAnnotations('plane'),

          appHost: domain,
        },
        ssl: {
          tls_secret_name: 'projects-dzerv-art-cert',
        },
        external_secrets: {
          silo_env_existingSecret: 'plane-silo-secrets',
        },
        env: {
          storageClass: 'openebs-replicated',
        },
        extraEnv: [
          { name: 'PAYMENT_SERVER_BASE_URL', value: prime_server },
          { name: 'FEATURE_FLAG_SERVER_BASE_URL', value: prime_server },
          { name: 'FEATURE_FLAG_SERVER_AUTH_TOKEN', value: 'hello_world' },
          { name: 'OPENAI_BASE_URL', value: 'https://api.z.ai/api/coding/paas/v4' },
          { name: 'TZ', value: timezone },
        ],
      },
    })
  )) + {
    // Add the magicentry.rs/enable label to the plane-api-wl deployment
    // by patching the deployment template in the Helm output
    deployment_plane_api_wl+: {
      spec+: {
        template+: {
          metadata+: {
            labels+: {
              'magicentry.rs/enable': 'true',
            },
          },
        },
      },
    },
  },

  planeSecrets: {
    apiVersion: 'external-secrets.io/v1',
    kind: 'ExternalSecret',
    metadata: {
      name: 'plane-silo-secrets',
      namespace: namespace,
    },
    spec: {
      refreshPolicy: 'OnChange',
      target: {
        template: {
          data: {
            SILO_HMAC_SECRET_KEY: '{{ .password }}',
          },
        },
      },
      dataFrom: [{
        sourceRef: {
          generatorRef: {
            apiVersion: 'generators.external-secrets.io/v1alpha1',
            kind: 'ClusterGenerator',
            name: 'password',
          },
        },
      }],
    },
  },

  // Allow magicentry (auth namespace) to reach Plane pods
  planeMagicentryNetworkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-plane-magicentry',
      namespace: namespace,
    },
    spec: {
      podSelector: {},
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'auth',
                },
              },
              podSelector: {
                matchLabels: {
                  'app.kubernetes.io/name': 'magicentry',
                },
              },
            },
          ],
        },
      ],
    },
  },

  planeN8NNetworkPolicy: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-plane-n8n',
      namespace: namespace,
    },
    spec: {
      podSelector: {},
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  'kubernetes.io/metadata.name': 'n8n',
                },
              },
              podSelector: {
                matchLabels: {
                  service: 'n8n',
                },
              },
            },
          ],
        },
      ],
    },
  },

  // Backup configurations for all Plane PVCs using the wrapper function
  planeBackups: gemini.backupMany(
    namespace=namespace,
    pvcClaimNames=[
      'pvc-plane-minio-vol-plane-minio-wl-0',
      'pvc-plane-monitor-vol-plane-monitor-wl-0',
      'pvc-plane-pgdb-vol-plane-pgdb-wl-0',
      'pvc-plane-rabbitmq-vol-plane-rabbitmq-wl-0',
      'pvc-plane-redis-vol-plane-redis-wl-0',
    ]
  ),
}
