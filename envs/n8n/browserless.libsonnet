local dockerService = import 'docker-service.libsonnet';

local namespace = 'n8n';
local domain = 'dzerv.art';

// Use TF-compatible labels for selector
local tfLabels = {
  managed_by: 'terraform',
  service: 'n8n-browserless',
};

local browserlessBase = dockerService.new('n8n-browserless', 'ghcr.io/browserless/chromium', {
  namespace: namespace,
  fqdn: 'browser.' + domain,
  ports: [3000],
  runAsUser: 999,  // BLESS_USER_ID env var
  labels: tfLabels,
  ingressAnnotations: {
    'nginx.ingress.kubernetes.io/auth-tls-secret': namespace + '/client-ca',
    'nginx.ingress.kubernetes.io/auth-tls-verify-client': 'on',
    'nginx.ingress.kubernetes.io/auth-tls-verify-depth': '1',
    'nginx.ingress.kubernetes.io/proxy-connect-timeout': '3600',
    'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
    'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600',
    'nginx.ingress.kubernetes.io/server-snippets': |||
      location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
      }
    |||,
  },
  env: {},

});

{
  // n8n-browserless deployment (headless browser for web scraping)
  // Don't create a new namespace since we use n8n namespace
  n8nBrowserless: browserlessBase {
    namespace:: null,  // Hide namespace creation

    workload+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: { provider: 'grnet' },
            containers: [
              super.containers[0] {
                env: [
                  {
                    name: 'TOKEN',
                    valueFrom: {
                      secretKeyRef: {
                        name: 'n8n-browserless-token',
                        key: 'token',
                        optional: false,
                      },
                    },
                  },
                  { name: 'ALLOW_GET', value: 'true' },
                  { name: 'CONCURRENT', value: '5' },
                  { name: 'PROXY_HOST', value: 'n8n-browserless.' + namespace + '.svc.cluster.local' },
                  { name: 'PROXY_PORT', value: '3000' },
                  { name: 'PROXY_SSL', value: 'false' },
                  { name: 'QUEUED', value: '10' },
                  { name: 'TIMEOUT', value: std.toString(15 * 60 * 1000) },
                ],
              },
            ],
          },
        },
      },
    },

    service+: {
      spec+: {
        ports: [{
          port: 3000,
          targetPort: 3000,
          protocol: 'TCP',
        }],
      },
    },
  },
}
