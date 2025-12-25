local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

dockerService.new('cliproxyapi', 'eceasy/cli-proxy-api', {
  fqdn: 'ai.vpn.dzerv.art',
  ports: [8317],
  args: ['./CLIProxyAPI', '-config', '/data/config.yaml'],

  pvs: {
    '/data': {
      name: 'cliproxyapi',
      size: '128Mi',
    },
  },
})
