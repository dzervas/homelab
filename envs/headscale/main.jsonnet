local dockerService = import 'docker-service.libsonnet';
local containerLib = import 'docker-service/container.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local gatewayApi = import 'gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local affinity = import 'helpers/affinity.libsonnet';
local k = import 'k.libsonnet';
local serviceAccount = k.core.v1.serviceAccount;
local clusterRole = k.rbac.v1.clusterRole;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local container = k.core.v1.container;
local envVar = k.core.v1.envVar;
local statefulSet = k.apps.v1.statefulSet;
local httpRoute = gatewayApi.gateway.v1.httpRoute;
local lab = import 'labsonnet.libsonnet';

local namespace = 'headscale';
local domain = 'dzerv.art';

local sharedPV = { '/data': { name: 'shared', empty_dir: true } };

{
  headscale:
    lab.new('headscale', 'ghcr.io/juanfont/headscale', ghcr=true)
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withArgs(['serve'])
    + lab.withPV('/var/lib/headscale', { name: 'db', size: '512Mi' })
    + lab.withPV('/data', { name: 'shared', readOnly: false, emptyDir: true })
    + lab.withConfigMapMount('/etc/headscale', 'headscale-config')
    + lab.withPublicHttp(8080, 'vpn.dzerv.art')
    + lab.withAffinityAvoidHomelab()
    + lab.withInitContainer(
      container.new('init-dns-json', 'busybox')
      + container.withCommand(['sh', '-c'])
      + container.withArgs(['printf "[]" > /data/dns.json'])
    )
    + lab.withContainer(
      container.new('dns-controller', 'ghcr.io/dzervas/dns-controller')
      + container.withEnv([
        { name: 'INGRESS_CLASS', value: 'traefik' },
        { name: 'DOMAIN_SUFFIX', value: 'ts.%s' % domain },
        { name: 'OUTPUT_PATH', value: '/data/dns.json' },
        { name: 'HEADSCALE_URL', value: 'http://127.0.0.1:8080' },
        { name: 'HEADSCALE_API_KEY', valueFrom: { secretKeyRef: { name: 'dns-controller-op', key: 'HEADSCALE_API_KEY' } } },
      ])
    )
    + { workload+: statefulSet.spec.template.spec.withServiceAccountName('dns-controller') },

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
              // https://adguard-dns.io/en/public-dns.html
              '94.140.14.14',
              '94.140.15.15',
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
}
