local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local gemini = import 'helpers/gemini.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'plane';
local domain = 'projects.dzerv.art';
local prime_server = 'http://plane-prime:8000';

{
  // NOTE: Creates the namespace
  planePrime: dockerService.new('plane-prime', 'ghcr.io/dzervas/plane-prime:latest', {
    namespace: namespace,
    port: 8000,
  }),
  plane: helm.template('plane', '../charts/plane-enterprise', {
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
        } + ingress.oidcAnnotations('plane'),

        appHost: domain,
      },
      ssl: {
        tls_secret_name: 'projects-dzerv-art-cert',
      },
      env: {
        storageClass: 'openebs-replicated',
      },
      extraEnv: [
        { name: 'PAYMENT_SERVER_BASE_URL', value: prime_server },
        { name: 'FEATURE_FLAG_SERVER_BASE_URL', value: prime_server },
        { name: 'FEATURE_FLAG_SERVER_AUTH_TOKEN', value: 'hello_world' },
        { name: 'OPENAI_BASE_URL', value: 'https://api.z.ai/api/coding/paas/v4' },
      ],
    },
  }) + {
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
