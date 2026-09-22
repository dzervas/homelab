local cidr = import 'cidr.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local users = import 'users.libsonnet';
local helm = tk.helm.new(std.thisFile);

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

// What the wireguard server listens on inside the pod
local wireguardPort = 51820;
// Inside RKE2's service-node-port-range (25000-32767), see nixos/rke2/config.nix
local wireguardNodePort = 25820;

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
      serviceType: 'NodePort',
      port: 25820,
      serviceAnnotations: { 'external-dns.kubernetes.io/hostname': 'wg.dzerv.art' },
      externalAddress: 'wg.dzerv.art',
      nodeSelector: { 'topology.kubernetes.io/zone': 'oracle' },

      peerCIDR: cidr.cidr,
      // TODO: Fix the search domain
      // dnsSearchDomain: 'vpn.dzerv.art',
      dns: '10.43.0.53',

      // A peer packet costs 60 bytes of overhead (32 wireguard + 28 IP/UDP) by
      // the time it reaches the server pod. The veth is 1420 and cross-node pod
      // routes are 1370, so the default 1420 fragments every full-size packet.
      mtu: '1300',

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
} + users

// To have IP survive up to traefik:
// - In the wg server (needs a fork of the operator, it doesn't allow for additional iptables rules since it runs iptables-restore without --noflush):
//   `-t nat -A PREROUTING -i wg0 -s 10.50.50.4/32 -d 10.43.0.50/32 -p tcp --dport 443 -j REDIRECT --to-port 8443`
// - HAProxy sidecar to the wg server that listens on 10.50.50.1 and forwards to traefik-vpn svc
// - Traefik `proxyProtocol: { trustedIPs: ['10.200.0.0/16'] }` (TBD if the service dns works too)
