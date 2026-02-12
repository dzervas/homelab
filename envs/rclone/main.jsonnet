local dockerService = import 'docker-service.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local k = import 'k.libsonnet';
local networkPolicy = k.networking.v1.networkPolicy;
local namespace = 'rclone';

{
  rclone: dockerService.new('rclone', 'rclone/rclone:1', {
    ports: [80],
    fqdn: 'webdav.dzerv.art',
    auth: 'mtls',

    command: ['sh', '-c'],
    args: [|||
      cp /secret/rclone.conf /tmp/rclone.conf
      # VFS Cache results in a horrible performance drop for round-trip write-read operations
      rclone serve webdav remote: --cache-dir /tmp/.cache --vfs-cache-mode full --addr 0.0.0.0:80 --config /tmp/rclone.conf --temp-dir /tmp --metrics-addr 0.0.0.0:9090
    |||],

    secrets: { '/secret': 'rclone-secrets-op:ro' },
  }),

  rcloneS3: dockerService.new('rclone-s3', 'rclone/rclone:1', {
    namespace: namespace,
    ports: [80],

    command: ['sh', '-c'],
    args: [|||
      cp /secret/rclone.conf /tmp/rclone.conf
      # VFS Cache results in a horrible performance drop for round-trip write-read operations
      rclone serve s3 s3: --cache-dir /tmp/.cache --vfs-cache-mode full --addr 0.0.0.0:80 --config /tmp/rclone.conf --temp-dir /tmp --metrics-addr 0.0.0.0:9090
    |||],

    secrets: { '/secret': 'rclone-secrets-op:ro' },
  }),

  secret:
    externalSecret.new('rclone-secrets-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'rclone' } }]),


  // networkPolicy:
  //   networkPolicy.new('allow-linstor')
  //   + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'rclone-s3' })
  //   + networkPolicy.spec.withPolicyTypes(['Ingress'])
  //   + networkPolicy.spec.withIngress([{
  //     from: [{
  //       // For some reason VPN CIDR doesn't work
  //       namespaceSelector: {},
  //       podSelector: { matchLabels: { 'ai/enable': 'true' } },
  //     }],
  //     ports: [{ port: 8317, protocol: 'TCP' }],
  //   }]),
}
