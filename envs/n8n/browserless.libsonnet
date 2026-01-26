local dockerService = import 'docker-service.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';

local namespace = 'n8n';
local domain = 'dzerv.art';

{
  // n8n-browserless deployment (headless browser for web scraping)
  // Uses dockerService like the original TF module
  n8nBrowserless: dockerService.new('n8n-browserless', 'ghcr.io/browserless/chromium', {
    namespace: namespace,
    type: 'Deployment',
    fqdn: 'browser.' + domain,
    ports: [3000],
    runAsUser: 999,  // BLESS_USER_ID env var

    ingressAnnotations:
      ingress.mtlsAnnotations(namespace)
      + {
        'nginx.ingress.kubernetes.io/proxy-connect-timeout': '3600',
        'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
        'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600',
        // From https://docs.browserless.io/enterprise/nginx-docker#nginxconf
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

    env: {
      ALLOW_GET: 'true',  // Required for some stuff in the n8n node
      PROXY_HOST: 'n8n-browserless.' + namespace + '.svc.cluster.local',
      PROXY_PORT: '3000',
      PROXY_SSL: 'false',
      CONCURRENT: '5',
      QUEUED: '10',
      TIMEOUT: std.toString(15 * 60 * 1000),
    },

    op_envs: {
      TOKEN: 'token',  // Uses n8n-browserless-token secret
    },
  }) {
    // Don't create a new namespace since we use n8n namespace
    namespace:: null,
    // The opsecret uses the wrong name, we use a generated password instead
    opsecret:: null,

    workload+: {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: { provider: 'grnet' },
          },
        },
      },
    },
  },
}
