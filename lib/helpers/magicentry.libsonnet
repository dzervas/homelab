{
  // Traefik forwardAuth middleware that gates requests behind magicentry.
  // Gateway API ExtensionRef filters can only reference middlewares in the
  // route's namespace, so labsonnet apps get their own copy.
  middleware(name):: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: name },
    spec: {
      forwardAuth: {
        address: 'http://magicentry.magicentry.svc.cluster.local:8080/auth-url/status',
        addAuthCookiesToResponse: ['magicentry_session_id'],
        maxResponseBodySize: 1048576,  // 1MB

        authRequestHeaders: ['Cookie'],
        authResponseHeaders: ['X-Remote-User', 'X-Remote-Groups'],
        preserveLocationHeader: true,
        trustForwardHeader: true,
      },
    },
  },

  // Service metadata magicentry watches to register the app
  serviceLabels:: { 'magicentry.rs/enable': 'true' },
  serviceAnnotations(name, fqdn, realms):: {
    'magicentry.rs/name': name,
    'magicentry.rs/url': 'https://' + fqdn,
    'magicentry.rs/realms': realms,
    // Traefik forwards websocket upgrades with X-Forwarded-Proto: wss, which
    // magicentry matches as a separate origin
    'magicentry.rs/auth_url_origins': 'https://%s,wss://%s' % [fqdn, fqdn],
  },
}
