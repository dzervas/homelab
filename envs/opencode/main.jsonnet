local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local namespace = 'opencode';
local image = 'ghcr.io/dzervas/opencode:latest';
local dataPath = '/data';
local configPath = '/config';

local configFile = configPath + '/opencode.json';

local opencode = dockerService.new('opencode', image, {
  namespace: namespace,
  ports: [4096],
  fqdn: 'opencode.vpn.dzerv.art',

  labels: { 'ai/enable': 'true' },

  env: {
    TZ: timezone,
    OPENCODE_CONFIG: configFile,
    XDG_DATA_HOME: dataPath,
  },

  // op_envs: { OPENCODE_SERVER_PASSWORD: 'password' },

  pvs: {
    [dataPath]: {
      name: 'data',
      size: '20Gi',
    },
  },

  config_maps: {
    '/env/.config/opencode/': 'opencode-config:ro',
  },
});

local configMap =
  k.core.v1.configMap.new('opencode-config')
  + k.core.v1.configMap.metadata.withNamespace(namespace)
  + k.core.v1.configMap.withData({
    'opencode.json': std.manifestJsonEx({
      '$schema': 'https://opencode.ai/config.json',
      autoupdate: false,
      server: {
        hostname: '0.0.0.0',
        port: 4096,
        cors: ['http://opencode.vpn.dzerv.art'],
      },
      provider: {
        dz: {
          models: {
            'gemini-3-pro-preview': {
              name: 'gemini-3-pro',
            },
            'gemini-claude-opus-4-5-thinking': {
              name: 'opus-4.5',
            },
            'gemini-sonnet-claude-4-5-thinking': {
              name: 'sonnet-4.5',
            },
            'glm-4.7': {
              name: 'glm-4.7',
            },
            'gpt-5.2(high)': {
              name: 'gpt-5.2',
            },
            'gpt-5.2-codex(high)': {
              name: 'gpt-5.2-codex-high',
            },
            'gpt-5.2-codex(medium)': {
              name: 'gpt-5.2-codex',
            },
          },
          name: 'DZervArt',
          npm: '@ai-sdk/anthropic',
          options: {
            apiKey: 'sk-dummy',
            baseURL: 'https://ai.vpn.dzerv.art/v1',
          },
        },
      },
      share: 'disabled',
      small_model: 'dz/glm-4.7',
    }, '  '),
  });

{
  opencode: opencode,
  opencodeConfig: configMap,
}
