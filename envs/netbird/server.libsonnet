local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local gatewayApi = import 'gateway-api-libsonnet/1.4-experimental/main.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local httpRoute = gatewayApi.gateway.v1.httpRoute;
local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;

local proxyPort = 8443;

local namespace = 'netbird';
local domain = 'netbird.dzerv.art';
local url = 'https://' + domain;
local issuer = url + '/oauth2';

// The combined server listens on a single port for HTTP, gRPC and WebSocket.
// 8080 instead of the default 80 so the container can run unprivileged.
local serverPort = 8080;
local serverLabels = { app: 'netbird-server', 'app.kubernetes.io/name': 'netbird-server' };

local pathPrefix(value) = { path: { type: 'PathPrefix', value: value } };

// Everything that is plain HTTP/WebSocket. gRPC is routed separately (h2c).
local httpPaths = ['/api', '/oauth2', '/relay', '/ws-proxy/'];
local grpcPaths = [
  '/signalexchange.SignalExchange/',
  '/management.ManagementService/',
  '/management.ProxyService/',
];

{
  server:
    lab.new('netbird-server', 'netbirdio/netbird-server:0.75.0')
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    + lab.withPV('/var/lib/netbird', { name: 'data', size: '5Gi' })
    + lab.withSecretMount('/etc/netbird', 'netbird-config')
    + lab.withPublicHttp(serverPort, domain, 'http', std.map(pathPrefix, httpPaths))
    + lab.withPort({ port: 9090, name: 'metrics' })
    + lab.withServiceMonitor('metrics', '/metrics')
    // NOT :9000/health - that endpoint dials the relay through its public URL, so it
    // stays 503 until traefik has a ready endpoint, which never happens if it gates
    // readiness. A TCP check on the serving port avoids the deadlock.
    + lab.withLivenessProbe({ tcpSocket: { port: serverPort }, initialDelaySeconds: 15, periodSeconds: 20 })
    + lab.withReadinessProbe({ tcpSocket: { port: serverPort }, initialDelaySeconds: 5, periodSeconds: 10 })
    + lab.withAffinityAvoidHomelab()
    // Allows talking to magicentry for the OIDC token/userinfo exchange
    + lab.withPodLabels({ 'magicentry.rs/enable': 'true' })
    + {
      service+:
        service.metadata.withLabels({ 'magicentry.rs/enable': 'true' })
        + service.metadata.withAnnotations({
          'magicentry.rs/name': 'NetBird',
          'magicentry.rs/url': url,
          'magicentry.rs/realms': 'netbird',
          'magicentry.rs/oidc_redirect_urls': issuer + '/callback',
        }),
    },

  proxy:
    lab.new('netbird-proxy', 'netbirdio/reverse-proxy:0.75.0')
    + lab.withNamespace(namespace)
    + lab.withSecretMount('/certs', 'netbird-proxy-tls')
    + lab.withPort({ port: proxyPort, name: 'tls' })
    + lab.withSecretEnv({ NB_PROXY_TOKEN: { name: 'netbird-proxy', key: 'token' } })
    + lab.withEnv({
      NB_PROXY_DOMAIN: 'vpn.dzerv.art',
      // Direct cluster-local gRPC connection; TLS is unnecessary inside the cluster.
      NB_PROXY_MANAGEMENT_ADDRESS: 'http://netbird-server:%d' % serverPort,
      NB_PROXY_ALLOW_INSECURE: 'true',
      // Advertise the embedded/private capability required by NetBird-Only Access.
      NB_PROXY_PRIVATE: 'true',
      NB_PROXY_ADDRESS: ':%d' % proxyPort,
      NB_PROXY_ACME_CERTIFICATES: 'false',
      NB_PROXY_CERTIFICATE_DIRECTORY: '/certs',
      NB_PROXY_LOG_LEVEL: 'info',
    })
    + lab.withAffinityAvoidHomelab(),

  // cert-manager keeps tls.crt/tls.key updated in this Secret; the proxy
  // watches static certificate files and reloads renewals automatically.
  proxyCert: {
    apiVersion: 'cert-manager.io/v1',
    kind: 'Certificate',
    metadata: {
      name: 'netbird-proxy',
      namespace: namespace,
    },
    spec: {
      secretName: 'netbird-proxy-tls',
      issuerRef: {
        name: 'letsencrypt',
        kind: 'ClusterIssuer',
      },
      dnsNames: ['*.vpn.dzerv.art'],
    },
  },

  // Traefik must speak HTTP/2 cleartext to the gRPC endpoints, which is selected
  // through appProtocol - hence a second service for the very same port.
  serverGrpcService:
    service.new('netbird-server-h2c', serverLabels, [
      servicePort.newNamed('grpc', serverPort, serverPort)
      + servicePort.withAppProtocol('kubernetes.io/h2c'),
    ])
    + service.metadata.withNamespace(namespace)
    + service.metadata.withLabels(serverLabels),

  serverGrpcRoute:
    httpRoute.new('netbird-server-grpc')
    + httpRoute.metadata.withNamespace(namespace)
    + httpRoute.metadata.withAnnotations({ 'cert-manager.io/cluster-issuer': 'letsencrypt' })
    + httpRoute.spec.withHostnames([domain])
    + httpRoute.spec.withParentRefs([
      httpRoute.spec.parentRefs.withName('traefik-gateway')
      + httpRoute.spec.parentRefs.withNamespace('traefik')
      + httpRoute.spec.parentRefs.withSectionName('websecure'),
    ])
    + httpRoute.spec.withRules([
      httpRoute.spec.rules.withMatches(std.map(pathPrefix, grpcPaths))
      + httpRoute.spec.rules.withBackendRefs([
        httpRoute.spec.rules.backendRefs.withName('netbird-server-h2c')
        + httpRoute.spec.rules.backendRefs.withPort(serverPort),
      ]),
    ]),

  // p run --rm -e NETBIRD_MGMT_API_ENDPOINT=https://netbird.dzerv.art -e NETBIRD_MGMT_GRPC_API_ENDPOINT=https://netbird.dzerv.art -e LETSENCRYPT_DOMAIN=none -e USE_AUTH0=false -e AUTH_AUTHORITY=https://netbird.dzerv.art/oauth2 -e AUTH_CLIENT_ID=netbird-dashboard -e AUTH_AUDIENCE=netbird-dashboard -e AUTH_SUPPORTED_SCOPES="openid profile email groups offline_access" -e AUTH_REDIRECT_URI=/nb-auth -e AUTH_SILENT_REDIRECT_URI=/nb-silent-auth -p 127.0.0.1:8080:8080 netbird-dashboard
  // Catch-all: anything that is not an API/gRPC path is the dashboard
  // dashboard:
  //   lab.new('netbird-dashboard', 'git.vpn.dzerv.art/dzervas/homelab/netbird-dashboard')
  //   + lab.withNamespace(namespace)
  //   // Repackaged onto nginx-unprivileged, see docker/netbird-dashboard - the stock
  //   // image needs root plus NET_BIND_SERVICE, CHOWN, SETUID and SETGID
  //   + lab.withPublicHttp(8080, domain)
  //   + lab.withRunAsUser(101)
  //   + lab.withEmptyDir('/tmp')
  //   + lab.withEnv({
  //     NETBIRD_MGMT_API_ENDPOINT: url,
  //     NETBIRD_MGMT_GRPC_API_ENDPOINT: url,

  //     // The embedded IdP - external providers are added at runtime, see below
  //     AUTH_AUTHORITY: issuer,
  //     AUTH_CLIENT_ID: 'netbird-dashboard',
  //     AUTH_AUDIENCE: 'netbird-dashboard',
  //     AUTH_SUPPORTED_SCOPES: 'openid profile email groups offline_access',
  //     AUTH_REDIRECT_URI: '/nb-auth',
  //     AUTH_SILENT_REDIRECT_URI: '/nb-silent-auth',
  //     USE_AUTH0: 'false',

  //     // TLS is terminated by traefik
  //     LETSENCRYPT_DOMAIN: 'none',
  //   }),

  config:
    externalSecret.new('netbird-config')
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'netbird' } }])
    + externalSecret.spec.target.template.withData({
      'config.yaml': std.manifestYamlDoc({
        server: {
          listenAddress: ':%d' % serverPort,
          // Address handed out to the peers, must be publicly reachable
          exposedAddress: url + ':443',
          metricsPort: 9090,
          healthcheckAddress: ':9000',
          logLevel: 'info',
          logFile: 'console',
          dataDir: '/var/lib/netbird/',

          // Relay authentication
          authSecret: '{{ .auth_secret }}',

          disableAnonymousMetrics: true,

          // TODO: STUN needs UDP/3478 reachable from the internet, which traefik
          // does not listen on - peers fall back to the relay until then
          stunPorts: [3478],

          auth: {
            issuer: issuer,
            localAuthDisabled: false,
            signKeyRefreshEnabled: true,
            dashboardRedirectURIs: [url + '/nb-auth', url + '/nb-silent-auth', 'http://127.0.0.1:8080/nb-auth', 'http://127.0.0.1:8080/nb-silent-auth'],
            cliRedirectURIs: ['http://localhost:53000/'],
            dashboardPostLogoutRedirectURIs: [url, 'http://127.0.0.1:8080'],
            // Bootstraps the first admin on an empty database.
            // owner_password must be a bcrypt hash, NOT plaintext - it is passed
            // straight to dex as the password hash:
            //   htpasswd -bnBC 10 "" 'password' | tr -d ':\n'
            owner: {
              email: '{{ .owner_email }}',
              password: '{{ .owner_hash }}',
            },
          },

          store: {
            engine: 'sqlite',
            // base64 of 32 random bytes: openssl rand -base64 32
            encryptionKey: '{{ .store_encryption_key }}',
          },
        },
      }),
    }),
}

// The embedded IdP (dex) does not read static connectors from config.yaml, so
// magicentry has to be registered through the API once the server is up. The
// client_id/client_secret are created by the magicentry annotations above:
//
// k -n netbird get secret netbird-server-magicentry -o yaml
// curl -X POST https://netbird.dzerv.art/api/identity-providers \
//   -H "Authorization: Token $NB_PAT" -H 'Content-Type: application/json' \
//   -d '{"type":"oidc","name":"MagicEntry","issuer":"https://auth.dzerv.art",
//        "client_id":"...","client_secret":"..."}'
//
// The PAT for the operator (secret netbird-op, key api-key) is created in the
// dashboard under Settings > Users > service user > Access Tokens.
//
// The reverse-proxy token is generated once and stored as `proxy_token` on the
// same 1Password item. It cannot be regenerated from the server because only
// its SHA-256 hash is retained:
//
// k create secret generic netbird-proxy --from-literal=token=(k -n netbird exec netbird-server-0 -- /go/bin/netbird-server --config /etc/netbird/config.yaml admin token create --name netbird-proxy | rg '^Token: ' | awk '{ print $2 }')
