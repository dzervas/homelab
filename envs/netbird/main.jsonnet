local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local server = import './server.libsonnet';

{
  namespace: k.core.v1.namespace.new('netbird'),

  operator:
    helm.template('netbird-operator', '../../charts/netbird-operator', {
      namespace: $.namespace.metadata.name,
      values: {
        clusterSecretsPermissions: { allowAllSecrets: false },

        // cluster: {
        //   dns: 'svc.cluster.local',
        //   name: 'kubernetes',
        // },

        // Self-hosted control plane, see server.libsonnet
        managementURL: 'https://netbird.dzerv.art',
        netbirdAPI: { keyFromSecret: { name: 'netbird-op', key: 'api-key' } },
      },
    }),

  operatorOpSecret: opsecretLib.new('netbird'),

  router: {
    apiVersion: 'netbird.io/v1alpha1',
    kind: 'NetworkRouter',
    metadata: {
      name: 'internal',
    },
    spec: {
      dnsZoneRef: {
        name: 'vpn.dzerv.art',
      },
    },
  },
} + server
