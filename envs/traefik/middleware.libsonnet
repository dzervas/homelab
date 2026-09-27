local magicentry = import 'helpers/magicentry.libsonnet';

{
  magicentry: magicentry.middleware('magicentry'),

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
