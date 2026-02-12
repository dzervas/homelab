{
  vpn: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'vpnonly' },
    spec: {
      ipAllowList: {
        sourceRange: ['100.100.50.0/24'],
      },
    },
  },

  magicentry: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'magicentry' },
    spec: {
      forwardAuth: {
        address: 'http://magicentry.auth.svc.cluster.local:8080/auth-url/status',
        addAuthCookiesToResponse: ['magicentry_session_id'],
        authResponseHeaders: ['Set-Cookie'],
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
