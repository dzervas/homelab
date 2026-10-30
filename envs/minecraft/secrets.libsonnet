local externalSecrets = import 'external-secrets.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local password = externalSecrets.generators.v1alpha1.password;

{
  credentials:
    externalSecret.new('minecraft-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withData([
      { secretKey: 'curseforge_api_key', remoteRef: { key: 'minecraft', property: 'curseforge_api_key' } },
      { secretKey: 'restic_password', remoteRef: { key: 'minecraft', property: 'restic_password' } },
      { secretKey: 'rclone_token', remoteRef: { key: 'minecraft', property: 'rclone_token' } },
      { secretKey: 'drive_id', remoteRef: { key: 'rclone', property: 'drive_id' } },
    ])
    + externalSecret.spec.target.template.withMergePolicy('Replace')
    + externalSecret.spec.target.template.withData({
      'curseforge-api-key': '{{ .curseforge_api_key }}',
      'restic-password': '{{ .restic_password }}',
      'rclone.conf': |||
        [remote]
        type = onedrive
        drive_type = business
        access_scopes = Files.ReadWrite.AppFolder Sites.Read.All offline_access Files.Read Files.ReadWrite
        no_versions = true
        hard_delete = true
        av_override = true
        metadata_permissions = read,write
        drive_id = {{ .drive_id }}
        token = {{ .rclone_token }}
      |||,
    }),

  rconPasswordGenerator:
    password.new('minecraft-rcon')
    + password.spec.withLength(40)
    + password.spec.withSymbols(0)
    + password.spec.withAllowRepeat(true),

  // Persist the generated password rather than producing a new value on every Tanka render
  rconPassword:
    externalSecret.new('minecraft-rcon')
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.target.template.withData({ 'rcon-password': '{{ .password }}' })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          name: 'minecraft-rcon',
        },
      },
    }]),
}
