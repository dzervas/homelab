local dockerService = import 'docker-service.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

{
  rclone: dockerService.new('gotify', 'ghcr.io/gotify/server', {
    ports: [8080],
    fqdn: 'notify.vpn.dzerv.art',

    pvs: {
      '/app/data': {
        name: 'data',
        size: '20Gi',
      },
    },

    env: {
      TZ: timezone,

      GOTIFY_SERVER_PORT: '8080',
      GOTIFY_SERVER_TRUSTEDPROXIES: '[10.42.0.0/16]',
      GOTIFY_SERVER_STREAM_ALLOWEDORIGINS: std.strReplace('[notify.vpn.dzerv.art]', '.', '\\.'),
    },

    op_envs: {
      GOTIFY_DEFAULTUSER_NAME: 'username',
      GOTIFY_DEFAULTUSER_PASS: 'password',
    },

    ingressAnnotations: {
      'nginx.ingress.kubernetes.io/proxy-body-size': '10g',
      'nginx.ingress.kubernetes.io/proxy-connect-timeout': '1m',
      'nginx.ingress.kubernetes.io/proxy-read-timeout': '1m',
      'nginx.ingress.kubernetes.io/proxy-send-timeout': '1m',

      // https://gotify.net/docs/nginx
      'nginx.ingress.kubernetes.io/server-snippets': |||
        location / {
          proxy_http_version 1.1;

          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";

          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto http;

          proxy_set_header Host $http_host;
        }
      |||,
    },
  }),
}
