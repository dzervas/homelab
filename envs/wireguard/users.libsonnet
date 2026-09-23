local cidr = import 'cidr.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local esPushSecret = externalSecrets.nogroup.v1alpha1.pushSecret;

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

  // Network devices
  userPolicy(cidr.prefix + '16', 443),
  userPolicy(cidr.prefix + '16', 22),
  userPolicy(cidr.prefix + '17', 443),
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

local userPeer(name, ip, admin=false, additionalPolicies=[], disablePolicies=false, pushSecret=false) = {
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

      egressNetworkPolicies: if disablePolicies then [{ to: {} }] else userPeerPolicies(name, ip, admin, additionalPolicies),
    },
  },
  ['peer-' + name + '-push']: if !pushSecret then null else
    esPushSecret.new('peer-' + name + '-push')
    + esPushSecret.spec.withDeletionPolicy('Delete')
    + esPushSecret.spec.withSecretStoreRefs([
      esPushSecret.spec.secretStoreRefs.withKind('ClusterSecretStore')
      + esPushSecret.spec.secretStoreRefs.withName('1password')
    ])
    + esPushSecret.spec.selector.secret.withName('users-peer-configs')
    + esPushSecret.spec.withData([
      esPushSecret.spec.data.match.withSecretKey('config')
      + esPushSecret.spec.data.match.remoteRef.withRemoteKey('zzz-%s-users-wireguard-config' % name)
    ])
    + esPushSecret.spec.template.withData({
      config: '{{ mustRegexReplaceAll "10.50.50.[0-9]+/32" (index . "users-%s" | replace "51820" "25820") "10.50.50.0/24, 10.43.0.0/24" }}\nPersistentKeepalive = 25' % name,
    })
};

// CIDRs: .0/30 is for internal services
// .0/28 is the admin subnet (0-15)
userPeer('dzervas-desktop', 4, true)
+ userPeer('dzervas-laptop', 5, true)
+ userPeer('dzervas-pixel', 6, true)

// .16/28 is the network devices subnet (16-31)
+ userPeer('modem', 16, disablePolicies=true)
+ userPeer('hass', 17)  // CLIProxyAPI access

// .128/25 is for other users (128-255)
+ userPeer('shed', 128, pushSecret=true)
+ userPeer('haris', 129)
