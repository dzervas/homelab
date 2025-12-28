local dockerService = import 'docker-service.libsonnet';
local namespace = 'rclone';

{
  rclone: dockerService.new('rclone', 'rclone/rclone:1', {
    namespace: namespace,
    ports: [80],
    fqdn: 'webdav.dzerv.art',

    command: ['sh', '-c'],
    args: [''],

    ingressAnnotations: {
      'nginx.ingress.kubernetes.io/proxy-body-size': '4g',
    },
  }),
}
