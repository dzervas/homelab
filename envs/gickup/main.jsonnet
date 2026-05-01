local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local lab = import 'labsonnet.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

local configMap = k.core.v1.configMap;

{
  // TODO: Turn into cron
  gickup:
    lab.new('gickup', 'ghcr.io/cooperspencer/gickup')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withArgs(['/config/config.yaml'])
    + lab.withPV('/data', { name: 'data', size: '10Gi' })
    + lab.withConfigMapMount('/config', 'gickup-config')
    + lab.withSecretMount('/secret', 'gickup-op')
    + lab.withEnv({ TZ: timezone }),

  gickupConfig:
    configMap.new('gickup-config')
    + configMap.withData({
      'config.yaml': std.manifestYamlDoc({
        // yaml-language-server: $schema=https://raw.githubusercontent.com/cooperspencer/gickup/refs/heads/main/gickup_spec.json
        source: {
          github: [{
            token_file: '/secret/github-read-token',
            user: 'dzervas',
            wiki: true,
            issues: true,
            // filter: { excludeforks: true }
          }]
        },
        destination: {
          'local': [{
            path: '/data',
            keep: 5,
            zip: true,
            lfs: true,
          }]
        }
      })
    }),

  gickupOpSecret: opsecretLib.new('gickup'),
}
