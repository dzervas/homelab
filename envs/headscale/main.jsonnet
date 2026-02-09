local dockerService = import 'docker-service.libsonnet';
local containerLib = import 'docker-service/container.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local gatewayApi = import 'gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local k = import 'k.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local serviceAccount = k.core.v1.serviceAccount;
local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local httpRoute = gatewayApi.gateway.v1.httpRoute;

local namespace = 'headscale';
local domain = 'dzerv.art';

local sharedPV = { '/data': { name: 'shared', empty_dir: true } };

{
  headscale:
    dockerService.new('headscale', 'ghcr.io/juanfont/headscale', {
      fqdn: 'vpn.' + domain,
      ports: [8080],
      args: ['serve'],
      pvs: sharedPV {
        '/var/lib/headscale': {
          name: 'db',
          size: '512Mi',
        },
      },
      config_maps: {
        '/etc/headscale': 'headscale-config:rw',
      },
    })
    + {
      namespace+: k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),
      workload+: {
        spec+: {
          template+: {
            spec+: {
              // SAs are pod-scoped so both containers are ran as dns-controller
              serviceAccountName: 'dns-controller',

              // Create dummy file to avoid headscale init error
              initContainers+: [
                containerLib.new(
                  'init-dns-json',
                  'gcr.io/distroless/base-nossl-debian12:debug',
                  pvs=sharedPV,
                  command=['sh', '-c'],
                  args=['printf "[]" > /data/dns.json'],
                ).container,
              ],
              containers+: [
                containerLib.new(
                  'dns-controller',
                  'ghcr.io/dzervas/dns-controller',
                  pvs=sharedPV,
                  op_envs={ HEADSCALE_API_KEY: 'HEADSCALE_API_KEY' },
                  env={
                    INGRESS_CLASS: 'vpn',
                    DOMAIN_SUFFIX: 'ts.%s' % domain,
                    OUTPUT_PATH: '/data/dns.json',
                    HEADSCALE_URL: 'http://127.0.0.1:8080',
                  },
                ).container,
              ],
            },
          },
        },
      },
    },

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
          extra_records_path: '/data/dns.json',
          override_local_dns: true,
          search_domains: ['vpn.%s' % domain],
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

        policy: {
          mode: 'file',
          path: '/etc/headscale/policies.hujson',
        },
      }),
      'policies.hujson': std.manifestJson({
        acls: [
          { action: 'accept', src: ['dzervas@'], dst: ['*:*'] },
          { action: 'accept', src: ['hass@'], proto: 'tcp', dst: ['srv0@:10300'] },  // Whisper
        ],
      }),
    }),

  dnsControllerServiceAccount: serviceAccount.new('dns-controller'),
  dnsControllerClusterRole:
    clusterRole.new('dns-controller')
    + clusterRole.withRules([
      {
        apiGroups: [''],
        resources: ['pods', 'services', 'nodes'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses'],
        verbs: ['get', 'list', 'watch'],
      },
    ]),

  dnsControllerClusterRoleBinding:
    clusterRoleBinding.new('dns-controller')
    + clusterRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + clusterRoleBinding.roleRef.withKind('ClusterRole')
    + clusterRoleBinding.roleRef.withName('dns-controller')
    + clusterRoleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: 'dns-controller',
      namespace: namespace,
    }]),

  dnsControllerOpSecret: opsecretLib.new('dns-controller'),

  httpRoute:
    httpRoute.new('headscale')
    + httpRoute.spec.withHostnames(['vpn.dzerv.art'])
    + httpRoute.spec.withParentRefs([{ name: 'cilium-gateway' }])
    + httpRoute.spec.withRules([{
      matches: [{
        path: { type: 'PathPrefix', value: '/' },
      }],
      backendRefs: [{ name: 'headscale', port: 8080 }],
    }]),
}
