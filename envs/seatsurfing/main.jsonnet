local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'seatsurfing';
local domain = 'book.synergastir.io';

{
  // Upstream ships no helm chart, only plain manifests: https://seatsurfing.io/docs/self-hosted/kubernetes/
  seatsurfing:
    lab.new('seatsurfing', 'ghcr.io/seatsurfing/backend:1.136.1')
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({
      'pod-security.kubernetes.io/enforce': 'restricted',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    })
    + lab.withRunAsUser(65532)
    // The only restricted requirement labsonnet doesn't already meet
    + lab.withPodSecurityContext({ seccompProfile: { type: 'RuntimeDefault' } })
    // Ingress instead of withPublicHttp: cert-manager's ingress-shim issues the cert (HTTP01)
    // without adding a listener and certificateRef to the shared gateway
    + lab.withPort({
      port: 8080,
      name: 'http',
      ingress: {
        fqdn: domain,
        clusterIssuer: 'letsencrypt',
        className: 'traefik',
        // Otherwise Traefik also routes it on websecure-vpn
        annotations: { 'traefik.ingress.kubernetes.io/router.entrypoints': 'websecure' },
      },
    })
    // Database and role come from envs/cloudnative-pg tenants
    + lab.withSecretEnv({
      POSTGRES_URL: { name: 'seatsurfing-postgres', key: 'uri' },
    })
    // CRYPT_KEY must be exactly 32 chars and never change: it encrypts DB fields
    // INIT_ORG_PASS only seeds the first admin on an empty database
    + lab.withOpEnvs({
      CRYPT_KEY: 'crypt-key',
      INIT_ORG_PASS: 'password',
      SMTP_AUTH_PASS: 'resend-api-key',
    }, 'seatsurfing')
    // Generated with:
    // openssl genrsa -traditional -out jwt.key 2048
    // openssl rsa -in jwt.key -pubout -out jwt.pub
    // op item edit seatsurfing "jwt-private-key[text]=$(cat jwt.key)" "jwt-public-key[text]=$(cat jwt.pub)"
    // shred -u jwt.key jwt.pub
    + lab.withSecretMount('/secret', 'seatsurfing-op')
    + lab.withEnv({
      // The first admin logs in as admin@<INIT_ORG_DOMAIN>
      INIT_ORG_DOMAIN: domain,
      DISABLE_ANONYMOUS_USAGE_STATS: '1',
      TZ: timezone,

      JWT_PRIVATE_KEY: '/secret/jwt-private-key',
      JWT_PUBLIC_KEY: '/secret/jwt-public-key',

      // Resend: STARTTLS only, the client has no implicit TLS (util/sendmail.go)
      // The sender's domain must be verified in Resend
      SMTP_HOST: 'smtp.resend.com',
      SMTP_PORT: '587',
      SMTP_START_TLS: '1',
      SMTP_AUTH: '1',
      SMTP_AUTH_USER: 'resend',
      MAIL_SENDER_ADDRESS: 'no-reply@synergastir.io',
    }),

  // Internet for the version check, OIDC, SMTP and CalDAV; in-cluster only Postgres
  egress: netpol.egress('seatsurfing-egress', namespace, { 'app.kubernetes.io/name': 'seatsurfing' }, {
    dnsNames: ['*'],
    cidrs: [netpol.internet],
    services: [{ namespace: 'postgres', name: 'shared-rw', ports: [{ port: 5432 }] }],
  }),
}
