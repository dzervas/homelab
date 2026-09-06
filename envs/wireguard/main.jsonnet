local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local cidrPrefix = '10.50.50.';
local userPeer(name, ip) = {
  apiVersion: 'vpn.wireguard-operator.io/v1alpha1',
  kind: 'WireguardPeer',
  metadata: {
    name: 'users-' + name,
  },
  spec: {
    wireguardRef: 'users',
    address: cidrPrefix + ip,
    allowedIPs: $.spec.address + '/32',

    egressNetworkPolicies: [
      {
        action: 'ACCEPT',
        protocol: 'TCP',
        to: {
          ip: '10.43.0.50',
          port: 443,
        },
      },
      {
        action: 'ACCEPT',
        protocol: 'UDP',
        to: {
          ip: '10.43.0.10',
          port: 53,
        },
      },
      {
        action: 'ACCEPT',
        protocol: 'TCP',
        to: {
          ip: '10.43.0.10',
          port: 53,
        },
      },
    ],
  },
};

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

      mtu: '1380',
      peerCIDR: cidrPrefix + '0/24',
      // dnsSearchDomain: 'vpn.dzerv.art',
      dns: '10.43.0.10',

      // tunnel: {
      //   enabled: true,
      //   type: 'wstunnel',  // only this is supported, https://github.com/NCCloud/wireguard-operator/blob/main/api/v1alpha1/wireguard_types.go
      //   dualMode: true,  // Support regular wg too
      // },
    },
  },

  users:
    std.map(function(ui) userPeer(ui.name, ui.ip), [
      // CIDRs: .0/30 is for internal services
      // .0/28 is the admin subnet (0-15)
      { name: 'dzervas-desktop', ip: 4 },
      { name: 'dzervas-laptop', ip: 5 },
      { name: 'dzervas-pixel', ip: 6 },

      // .128/25 is for other users (128-255)
      { name: 'shed', ip: 128 },
      { name: 'haris', ip: 129 },
    ]),

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
}
