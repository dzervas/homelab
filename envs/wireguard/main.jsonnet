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

// To have IP survive up to traefik:
// - In the wg server (needs a fork of the operator, it doesn't allow for additional iptables rules since it runs iptables-restore without --noflush):
//   `-t nat -A PREROUTING -i wg0 -s 10.50.50.4/32 -d 10.43.0.50/32 -p tcp --dport 443 -j REDIRECT --to-port 8443`
// - HAProxy sidecar to the wg server that listens on 10.50.50.1 and forwards to traefik-vpn svc
// - Traefik `proxyProtocol: { trustedIPs: ['10.200.0.0/16'] }` (TBD if the service dns works too)
