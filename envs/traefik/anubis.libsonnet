local lab = import 'labsonnet.libsonnet';

{
  anubis:
    lab.new('anubis', 'ghcr.io/techarohq/anubis')
    + lab.withNamespace('traefik')
    + lab.withPort({ name: 'metrics', port: 9090 })
    + lab.withPublicHttp(8080, fqdn='anubis.dzerv.art')
    + lab.withServiceMonitor('metrics', '/')
    + lab.withEnv({
      BIND: ':8080',
      TARGET: ' ',  // There's no backend, it's just forwardAuth

      PUBLIC_URL: 'https://anubis.dzerv.art',
      COOKIE_DOMAIN: 'dzerv.art',
      REDIRECT_DOMAINS: 'dzerv.art,*.dzerv.art',
      WEBMASTER_EMAIL: 'dzervas@dzervas.gr',

      COOKIE_EXPIRATION_TIME: std.toString(30 * 24) + 'h',
    }),

  middleware: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: 'anubis' },
    spec: {
      forwardAuth: {
        address: 'http://anubis:8080/.within.website/x/cmd/anubis/api/check',
      },
    },
  },
}
