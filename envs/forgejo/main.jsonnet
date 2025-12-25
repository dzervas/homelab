local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

dockerService.new('forgejo', 'codeberg.org/forgejo/forgejo:13-rootless', {
  fqdn: 'git.vpn.dzerv.art',
  ports: [3000],

  envs: { TZ: timezone },

  pvs: {
    '/var/lib/gitea': {
      name: 'data',
      size: '10Gi',
    },
    '/etc/gitea': {
      name: 'config',
      size: '128Mi',
    },
  },
})
