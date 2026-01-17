local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local namespace = 'opencode';
local image = 'ghcr.io/dzervas/opencode:latest';
local dataPath = '/data';
local configPath = '/config';

local serverArgs = ['web', '--hostname', '0.0.0.0', '--port', '4096'];
local configFile = configPath + '/opencode.json';

local opencode = dockerService.new('opencode', image, {
  namespace: namespace,
  ports: [4096],
  fqdn: 'opencode.vpn.dzerv.art',
  runAsUser: 1000,

  command: ['opencode'],
  args: serverArgs,

  env: {
    TZ: timezone,
    OPENCODE_CONFIG: configFile,
    XDG_DATA_HOME: dataPath,
  },

  op_envs: {
    OPENCODE_SERVER_PASSWORD: 'server-password',
  },

  pvs: {
    [dataPath]: {
      name: 'data',
      size: '20Gi',
    },
  },

  config_maps: {
    [configPath]: 'opencode-config:ro',
  },
});

local configMap = k.core.v1.configMap.new('opencode-config')
  + k.core.v1.configMap.metadata.withNamespace(namespace)
  + k.core.v1.configMap.withData({
    'opencode.json': std.manifestJsonEx({
      '$schema': 'https://opencode.ai/config.json',
      server: {
        hostname: '0.0.0.0',
        port: 4096,
      },
    }, '  '),
  });

{
  opencode: opencode,
  opencodeConfig: configMap,
}
