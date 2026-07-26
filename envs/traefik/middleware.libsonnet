{
  vpn: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'vpnonly' },
    spec: {
      ipAllowList: {
        sourceRange: [
          '100.100.50.0/24',  // headscale tailnet

          // TODO: netbird routing peers - verify the real source in the traefik
          // access log before trusting this. The router masquerades, so traefik
          // sees the routing peer pod instead of the peer's 100.124.x.x address,
          // and traefik is hostNetwork so cilium may SNAT it to the node IP.
          // '10.200.0.0/16',
        ],
      },
    },
  },

  magicentry: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'magicentry' },
    spec: {
      forwardAuth: {
        address: 'http://magicentry.magicentry.svc.cluster.local:8080/auth-url/status',
        addAuthCookiesToResponse: ['magicentry_session_id'],
        maxResponseBodySize: 1048576,  // 1MB
      },
    },
  },

  mtls: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'TLSOption',
    metadata: { name: 'mtls' },
    spec: {
      clientAuth: {
        secretNames: ['client-ca'],
        clientAuthType: 'RequireAndVerifyClientCert',
      },
    },
  },
}
