local externalSecrets = import 'external-secrets-libsonnet/1.1/main.libsonnet';
local gatewayApi = import 'gateway-api.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';

local helm = tk.helm.new(std.thisFile);
local clusterGenerator = externalSecrets.generators.v1alpha1.clusterGenerator;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local httpRoute = gatewayApi.gateway.v1.httpRoute;

local namespace = 'couchdb';
local domain = 'couchdb.vpn.dzerv.art';
local secretName = 'couchdb-admin';
local routeName = 'couchdb-vpn';

// Browser PouchDB always sends `credentials: 'include'`, and CouchDB refuses to
// combine `origins = *` with `credentials = true`, so every app origin that is
// allowed to sync has to be listed explicitly here.
local corsOrigins = ['https://' + domain];

local traefikGateway = {
  name: 'traefik-gateway',
  namespace: 'traefik',
  sectionName: 'websecure',
};

{
  namespace: k.core.v1.namespace.new(namespace),

  // The shared `password` ClusterGenerator emits a single `password` key and is
  // consumed by bugsink/n8n, so CouchDB gets its own generator that emits one
  // independent password per key the chart's Secret requires.
  passwordGenerator:
    clusterGenerator.new('couchdb-passwords')
    + clusterGenerator.spec.withKind('Password')
    + clusterGenerator.spec.generator.passwordSpec.withLength(50)
    + clusterGenerator.spec.generator.passwordSpec.withAllowRepeat(true)
    // The erlang cookie and the admin password end up in an ini file and in a
    // basic-auth header, so keep them alphanumeric.
    + clusterGenerator.spec.generator.passwordSpec.withSymbols(0)
    + clusterGenerator.spec.generator.passwordSpec.withSecretKeys([
      'adminPassword',
      'cookieAuthSecret',
      'erlangCookie',
    ]),

  // CreatedOnce: re-rolling erlangCookie would break the erlang distribution and
  // re-rolling cookieAuthSecret would invalidate every live _session cookie.
  adminSecret:
    externalSecret.new(secretName)
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.withRefreshPolicy('CreatedOnce')
    + externalSecret.spec.target.withName(secretName)
    + externalSecret.spec.target.template.withMergePolicy('Merge')
    + externalSecret.spec.target.template.withData({ adminUsername: 'admin' })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'couchdb-passwords',
        },
      },
    }]),

  couchdb:
    helm.template('couchdb', '../../charts/couchdb', {
      namespace: namespace,
      values: {
        // Longhorn already replicates the volume, so a single node avoids the
        clusterSize: 1,

        createAdminSecret: false,
        extraSecretName: secretName,

        persistentVolume: {
          enabled: true,
          size: '10Gi',
        },

        // The chart's setup job is a `helm.sh/hook: post-install`, which Tanka
        // has no concept of, so it would be applied immediately, race the
        // StatefulSet and then churn on every apply thanks to its
        // ttlSecondsAfterFinished. The cluster is finished once, by hand.
        // k -n couchdb exec sts/couchdb-couchdb -c couchdb -- sh -c 'curl -s -X POST http://127.0.0.1:5984/_cluster_setup -H "Content-Type: application/json" -d "{\"action\":\"finish_cluster\"}" -u $COUCHDB_USER:$COUCHDB_PASSWORD'
        autoSetup: { enabled: false },

        couchdbConfig: {
          couchdb: {
            // The chart requires an explicit UUID because a generated one would
            // change on every render. It identifies this server instance in
            // replication checkpoints, so it must stay stable.
            uuid: '5d6accd24f375a3204f83712eef8c571',
          },
          chttpd: {
            bind_address: 'any',
            enable_cors: true,
            // Only /_up stays anonymous, so the probes keep working while
            // everything else needs credentials.
            require_valid_user: false,
            require_valid_user_except_for_up: true,
            // Applies to _bulk_docs and attachments, not just single documents.
            max_http_request_size: 4294967296,
          },
          httpd: { 'WWW-Authenticate': 'Basic realm="administrator"'},
          chttpd_auth: {
            // PouchDB authenticates with POST /_session and relies on the
            // browser replaying the AuthSession cookie on cross-origin syncs.
            same_site: 'none',
          },
          cors: {
            credentials: true,
            origins: std.join(',', corsOrigins),
            headers: 'accept, authorization, content-type, origin, referer',
            methods: 'GET,PUT,POST,HEAD,DELETE',
          },
          couch_peruser: {
            enable: true,
            database_prefix: 'userdb-',
          },
        },

        // Exposed through the Gateway API below instead.
        ingress: { enabled: false },
      },
    }),

  // Same shape as labsonnet's withVpnHttp: a local chain middleware pointing at
  // traefik/vpnonly, attached to the route as an ExtensionRef filter.
  vpnMiddleware: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'Middleware',
    metadata: { name: routeName, namespace: namespace },
    spec: {
      chain: { middlewares: [{ name: 'vpnonly', namespace: 'traefik' }] },
    },
  },

  httpRoute:
    httpRoute.new(routeName)
    + httpRoute.metadata.withNamespace(namespace)
    + httpRoute.metadata.withAnnotations({ 'cert-manager.io/cluster-issuer': 'letsencrypt' })
    + httpRoute.spec.withHostnames([domain])
    + httpRoute.spec.withParentRefs([
      httpRoute.spec.parentRefs.withName(traefikGateway.name)
      + httpRoute.spec.parentRefs.withNamespace(traefikGateway.namespace)
      + httpRoute.spec.parentRefs.withSectionName(traefikGateway.sectionName),
    ])
    + httpRoute.spec.withRules([
      httpRoute.spec.rules.withMatches([
        httpRoute.spec.rules.matches.path.withType('PathPrefix')
        + httpRoute.spec.rules.matches.path.withValue('/'),
      ])
      + httpRoute.spec.rules.withFilters([{
        type: 'ExtensionRef',
        extensionRef: {
          group: 'traefik.io',
          kind: 'Middleware',
          name: routeName,
        },
      }])
      + httpRoute.spec.rules.withBackendRefs([
        httpRoute.spec.rules.backendRefs.withName('couchdb-couchdb')
        + httpRoute.spec.rules.backendRefs.withPort(5984),
      ]),
    ]),
}
