local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

dockerService.new('atuin', 'ghcr.io/atuinsh/atuin', {
  // TODO: Support statefulsets and args
  args: ['server', 'start'],

  ingressEnabled: false,
  port: 8888,

  env: {
    ATUIN_HOST: '0.0.0.0',
    ATUIN_PORT: '8888',
    ATUIN_OPEN_REGISTRATION: 'false',
    ATUIN_DB_URI: 'sqlite:///db/atuin.db',
    RUST_LOG: 'info',  // "info,atuin_server=debug"
    TZ: timezone,
  },

  pvs: {
    '/db': {
      name: 'db',
      size: '1Gi',
    },
  },
})
