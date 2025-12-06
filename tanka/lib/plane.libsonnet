local dockerService = import 'docker-service.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local gemini = import 'lib/gemini.libsonnet';
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
      planeVersion: 'stable',
      ingress: {
        enabled: true,
        ingressClass: 'nginx',
        ingress_annotations: {
          'cert-manager.io/cluster-issuer': 'letsencrypt',
          'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
          'nginx.ingress.kubernetes.io/auth-tls-verify-client': 'on',
          'nginx.ingress.kubernetes.io/auth-tls-secret': '%s/client-ca' % namespace,
          'nginx.ingress.kubernetes.io/auth-tls-verify-depth': '1',
          'nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream': 'true',
          'nginx.ingress.kubernetes.io/proxy-body-size': '5m',
        },

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
        { name: 'OPENAI_BASE_URL', value: 'https://api.z.ai/api/coding/paas/v4' },
      ],
    },
  }),

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
