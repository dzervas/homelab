local cidr = import 'cidr.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local users = import 'users.libsonnet';
local helm = tk.helm.new(std.thisFile);


{
  namespace: k.core.v1.namespace.new('wireguard'),

  operator:
    helm.template('wireguard', '../../charts/wireguard-operator', {
      namespace: $.namespace.metadata.name,
      values: {},
    }),

  server: {
    apiVersion: 'vpn.wireguard-operator.io/v1alpha1',
    kind: 'Wireguard',
    metadata: { name: 'users' },
    spec: {
      serviceType: 'ClusterIP',
      externalAddress: 'dzerv.art',
      nodeSelector: {
        'topology.kubernetes.io/zone': 'oracle',
      },

      peerCIDR: cidr.cidr,
      // TODO: Fix the search domain
      // dnsSearchDomain: 'vpn.dzerv.art',
      dns: '10.43.0.53',

      // tunnel: {
      //   enabled: true,
      //   type: 'wstunnel',  // only this is supported, https://github.com/NCCloud/wireguard-operator/blob/main/api/v1alpha1/wireguard_types.go
      //   dualMode: true,  // Support regular wg too
      // },
    },
  },

  // Prevent the descheduler from repeatedly evicting the single VPN gateway.
  pdb:
    k.policy.v1.podDisruptionBudget.new('users')
    + k.policy.v1.podDisruptionBudget.spec.withMinAvailable(1)
    + k.policy.v1.podDisruptionBudget.spec.selector.withMatchLabels({
      app: 'wireguard',
      instance: 'users',
    }),

  udpRoute: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'IngressRouteUDP',
    metadata: { name: 'wireguard' },
    spec: {
      entryPoints: ['wireguard'],
      routes: [{
        services: [{
          name: 'users-svc',
          port: 51820,
        }],
      }],
    },
  },
} + users
