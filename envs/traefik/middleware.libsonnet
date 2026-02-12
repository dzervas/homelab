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
}
