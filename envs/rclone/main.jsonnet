local dockerService = import 'docker-service.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local namespace = 'rclone';

{
  rclone: dockerService.new('rclone', 'rclone/rclone:1', {
    namespace: namespace,
    ports: [80],
    fqdn: 'webdav.dzerv.art',

    command: ['sh', '-c'],
    args: [|||
      cp /secret/rclone.conf /tmp/rclone.conf
      # VFS Cache results in a horrible performance drop for round-trip write-read operations
      rclone serve webdav remote: --cache-dir /tmp/.cache --vfs-cache-mode full --addr 0.0.0.0:80 --config /tmp/rclone.conf --temp-dir /tmp --metrics-addr 0.0.0.0:9090
    |||],

    secrets: { '/secret': 'rclone-secrets-op' },

    ingressAnnotations: {
      'nginx.ingress.kubernetes.io/proxy-body-size': '4g',
    },
  }),

  secret:
    externalSecret.new('rclone-secrets-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'rclone' } }]),
}
