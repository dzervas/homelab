local cidr = import 'cidr.libsonnet';

local userPolicy(ip, port, proto='TCP') = {
  action: 'ACCEPT',
  protocol: proto,
  to: { ip: ip, port: port },
};

local userPeerAdminPolicies = [
  // kube-api
  userPolicy('10.43.0.1', 443),
  // Forgejo SSH
  userPolicy('10.43.0.50', 2222),
];

local userPeerPolicies(name, ip, admin=false, additionalPolicies=[]) =
  [
    // Traefik
    userPolicy('10.43.0.50', 443),
    // CoreDNS
    userPolicy('10.43.0.53', 53, 'UDP'),
    userPolicy('10.43.0.53', 53, 'TCP'),
  ] + additionalPolicies + (
    if admin then userPeerAdminPolicies else []
  );

local userPeer(name, ip, admin=false, additionalPolicies=[], disablePolicies=false) = {
  ['peer-' + name]: {
    apiVersion: 'vpn.wireguard-operator.io/v1alpha1',
    kind: 'WireguardPeer',
    metadata: {
      name: 'users-' + name,
    },
    spec: {
      wireguardRef: 'users',
      address: cidr.prefix + ip,
      allowedIPs: cidr.prefix + ip + '/32',

      egressNetworkPolicies: if disablePolicies then [] else userPeerPolicies(name, ip, admin, additionalPolicies),
    },
  },
};

// CIDRs: .0/30 is for internal services
// .0/28 is the admin subnet (0-15)
userPeer('dzervas-desktop', 4, true)
+ userPeer('dzervas-laptop', 5, true)
+ userPeer('dzervas-pixel', 6, true)

// .16/28 is the network devices subnet (16-31)
+ userPeer('router', 16, disablePolicies=true)
+ userPeer('hass', 17)  // CLIProxyAPI access

// .128/25 is for other users (128-255)
+ userPeer('shed', 128)
+ userPeer('haris', 129)
