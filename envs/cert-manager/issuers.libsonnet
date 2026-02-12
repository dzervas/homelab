local cm = import 'cert-manager-libsonnet/1.19/main.libsonnet';
local clusterIssuer = cm.nogroup.v1.clusterIssuer;

local domain = 'dzerv.art';

{
  // Self-signed ClusterIssuer (used for CA certificates)
  selfSigned:
    clusterIssuer.new('selfsigned')
    + { spec+: { selfSigned: {} } },

  // Let's Encrypt ClusterIssuer for public certificates
  letsencrypt:
    clusterIssuer.new('letsencrypt')
    + clusterIssuer.spec.acme.withEmail('dzervas+homelab@dzervas.gr')
    + clusterIssuer.spec.acme.withServer('https://acme-v02.api.letsencrypt.org/directory')
    + clusterIssuer.spec.acme.privateKeySecretRef.withName('cert-manager-cluster-issuer-account-key')
    + clusterIssuer.spec.acme.withSolvers([
      {
        dns01: {
          cloudflare: {
            email: 'dzervas@dzervas.gr',
            apiTokenSecretRef: {
              name: 'cert-manager-op',
              key: 'cloudflare-api-token',
            },
          },
        },
        selector: {
          dnsNames: [
            domain,
            '*.' + domain,
          ],
        },
      },
      {
        http01: {
          ingress: {
            ingressClassName: 'traefik',
          },
        },
      },
    ]),
}
