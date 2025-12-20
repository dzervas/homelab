local dockerService = import 'docker-service.libsonnet';
local k = import 'k.libsonnet';

local namespace = 'headscale';
local domain = 'dzerv.art';

{
  headscale: dockerService.new('headscale', 'ghcr.io/juanfont/headscale', {
    namespace: namespace,
    fqdn: 'vpn.' + domain,
    ports: [8080],
    args: ['serve'],
    pvs: {
      '/var/lib/headscale': {
        name: 'db',
        size: '512Mi',
      },
    },
    config_maps: {
      '/etc/headscale': 'headscale-config:rw',
    },
  }),

  headscaleConfig:
    k.core.v1.configMap.new('headscale-config')
    + k.core.v1.configMap.metadata.withNamespace(namespace)
    + k.core.v1.configMap.withData({
      'config.yaml': std.manifestYamlDoc({
        disable_check_updates: true,
        server_url: 'https://vpn.%s' % domain,
        listen_addr: '0.0.0.0:8080',
        // metrics_listen_addr: '0.0.0.0:9090',
        noise: {
          private_key_path: '/var/lib/headscale/noise_private.key',
        },
        database: {
          type: 'sqlite3',
          sqlite: {
            path: '/var/lib/headscale/db.sqlite',
            write_ahead_log: true,
            wal_autocheckpoint: 1000,
          },
        },
        dns: {
          // NOTE: Enabling android private dns (DoH) will break magicdns!
          magic_dns: true,
          base_domain: 'ts.%s' % domain,
          extra_records_path: '/etc/headscale/dns.json',
          override_local_dns: true,
          nameservers: {
            global: [
              '8.8.8.8',
              '1.1.1.1',
            ],
          },
        },
        prefixes: {
          allocation: 'sequential',
          v4: '100.100.50.0/24',
        },
        derp: {
          server: {
            enabled: false,
            region_id: 999,
            region_code: 'homelab',
            region_name: 'HomeLab',
            verify_clients: true,
          },
          urls: [
            'https://controlplane.tailscale.com/derpmap/default',
          ],
          auto_update_enabled: true,
          update_frequency: '24h',
        },
        ephemeral_node_inactivity_timeout: '30m',
        unix_socket: '/tmp/headscale.sock',
        unix_socket_permission: '0700',
      }),
      'dns.json': '[]',
    }),

  dnsController: dockerService.new('dns-controller', 'ghcr.io/dzervas/dns-controller', {
    namespace: namespace,
    env: {
      INGRESS_CLASS: 'vpn',
      DOMAIN_SUFFIX: 'ts.%s' % domain,
      OUTPUT_PATH: '/data/dns.json',
      HEADSCALE_URL: 'http://headscale:8080',
    },
    op_envs: ['HEADSCALE_API_KEY'],
    config_maps: {
      '/data': 'headscale-config:rw',
    },
  }),
}
