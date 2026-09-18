local cidrPrefix = (import 'cidr.libsonnet').prefix;

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

local userPeerPolicies(name, ip, admin=false, additionalIPs=[]) = [
  // Traefik
  userPolicy('10.43.0.50', 443),
  // CoreDNS
  userPolicy('10.43.0.53', 53, 'UDP'),
  userPolicy('10.43.0.53', 53, 'TCP'),
] + (
  if admin then userPeerAdminPolicies else []
);

local userPeer(name, ip, admin=false, additionalIPs=[]) = {
  apiVersion: 'vpn.wireguard-operator.io/v1alpha1',
  kind: 'WireguardPeer',
  metadata: {
    name: 'users-' + name,
  },
  spec: {
    wireguardRef: 'users',
    address: cidrPrefix + ip,
    allowedIPs: $.spec.address + '/32',

    egressNetworkPolicies: userPeerPolicies(name, ip, admin, additionalIPs),
  },
};

// CIDRs: .0/30 is for internal services
// .0/28 is the admin subnet (0-15)
userPeer('dzervas-desktop', 4, true)
+ userPeer('dzervas-laptop', 5, true)
+ userPeer('dzervas-pixel', 6, true)

// .128/25 is for other users (128-255)
+ userPeer('shed', 128)
+ userPeer('haris', 129)
