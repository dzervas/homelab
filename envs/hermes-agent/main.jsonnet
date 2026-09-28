local externalSecrets = import 'external-secrets.libsonnet';
local gatewayApi = import 'gateway-api.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local httpRoute = gatewayApi.gateway.v1.httpRoute;
local service = k.core.v1.service;
local helm = tk.helm.new(std.thisFile);

local namespace = 'hermes-agent';
local domain = 'hermes.vpn.dzerv.art';
local name = 'hermes';
local dashboardPort = 9119;
local chromePort = 9222;
local signalPort = 8080;

// Labels the operator puts on the agent pod
local agentLabels = {
  'app.kubernetes.io/name': 'hermes-agent',
  'app.kubernetes.io/instance': name,
};

{
  namespace: k.core.v1.namespace.new(namespace),

  operator: helm.template('hermes-agent-operator', '../../charts/hermes-agent-operator', {
    namespace: namespace,
    values: {
      manager: { heartbeat: { enabled: false } },  // PostHog call-home
    },
  }),

  // Every field of the 1Password item becomes an env var of the agent (envFrom):
  // SIGNAL_ACCOUNT (the bot's E.164 number), SIGNAL_ALLOWED_USERS,
  // SIGNAL_GROUP_ALLOWED_USERS, plus any tool credentials like FORGEJO_TOKEN. Labels must be valid, unique
  // env var names; changes need a pod restart
  secret:
    externalSecret.new('hermes-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'hermes-agent' } }]),

  // The operator runs `gateway run` (Signal) and the image's s6 brings up the
  // dashboard alongside it when HERMES_DASHBOARD=1.
  // cliproxyapi is reachable through its networkPolicy, as operator 0.10.0 has
  // no spec.podLabels for 'ai/enable' (see envs/cliproxyapi networkPolicy)
  hermesAgent: {
    apiVersion: 'agents.hermeum.app/v1alpha1',
    kind: 'HermesAgent',
    metadata: { name: name },
    spec: {
      hermes: {
        image: { tag: 'v2026.9.24' },
        config: {
          raw: {
            theme: 'mono',
            font: 'inter',
            model: {
              provider: 'custom',
              base_url: 'http://cliproxyapi.cliproxyapi.svc:8317/v1',
              api_key: 'sk-dummy',
              default: 'gpt-6-luna',
            },
            // The chrome sidecar; Hermes resolves the ws URL via /json/version
            browser: { cdp_url: 'http://localhost:%d' % chromePort },
            dashboard: {
              // Also the only Host the dashboard's DNS-rebinding guard accepts
              public_url: 'https://' + domain,
              // Public PKCE client, magicentry names it kube-<magicentry.rs/name>
              oauth: {
                provider: 'self-hosted',
                self_hosted: { issuer: 'https://auth.dzerv.art', client_id: 'kube-Hermes' },
              },
            },

            // terminal: {
            //   env_passthrough: ['FORGEJO_TOKEN']
            // }
          },
        },
        storage: { persistence: { enabled: true } },
        // The operator sets no fsGroup and init-hermes runs as 10000, so the fresh PV
        // stays root-owned without this
        initChownData: true,
        env: [
          { name: 'HERMES_DASHBOARD', value: '1' },
          { name: 'TZ', value: timezone },
          { name: 'SIGNAL_HTTP_URL', value: 'http://localhost:%d' % signalPort },
        ],
        // Pre-create the sidecar's subPath as the hermes user; kubelet would
        // create it root-owned
        initScripts: [{ name: 'signal-cli-dir', script: 'mkdir -p "$HERMES_HOME/signal-cli"' }],
        envFrom: [{ secretRef: { name: 'hermes-op' } }],
      },

      // A single long-lived Chrome, so tabs and cookies persist across tasks
      // until the pod restarts. browserless would launch a fresh browser per
      // CDP connection, which breaks Hermes reconnecting to its pages
      sidecars: [{
        name: 'chrome',
        image: 'chromedp/headless-shell:stable',
        imagePullPolicy: 'Always',
        ports: [{ name: 'cdp', containerPort: chromePort }],
        // Chrome crashes with BUS_ADRERR on the default 64Mi /dev/shm. dshm is
        // the operator's own 1Gi memory emptyDir for the hermes container
        volumeMounts: [{ name: 'dshm', mountPath: '/dev/shm' }],
      }, {
        // No -a: multi-account mode starts before the number is registered, and
        // Hermes passes the account on every call. The account keys live on the
        // agent PV, the ghcr.io/asamk image is stuck on 0.13
        name: 'signal-cli',
        image: 'registry.gitlab.com/packaging/signal-cli/signal-cli-jre:latest',
        imagePullPolicy: 'Always',
        // The daemon prints every received message to stdout by default, which
        // would land in the pod logs; --scrub-log drops numbers/UUIDs from the rest
        args: [
          '--config',
          '/var/lib/signal-cli',
          '--scrub-log',
          'daemon',
          '--http',
          '127.0.0.1:%d' % signalPort,
          '--no-receive-stdout',
        ],
        securityContext: { runAsUser: 10000, runAsGroup: 10000 },
        volumeMounts: [{ name: 'hermes-data', mountPath: '/var/lib/signal-cli', subPath: 'signal-cli' }],
      }],
    },
  },

  // The operator's Service only exposes the API server/webhook ports, and has
  // no labels for magicentry to pick it up.
  // magicentry matches the redirect URL exactly and gates it on the realms;
  // the dashboard has no group allowlist of its own
  dashboardService:
    // Not hermes-*: service links would inject HERMES_DASHBOARD_PORT=tcp://...
    service.new('dashboard', agentLabels, [{ name: 'http', port: dashboardPort, targetPort: dashboardPort }])
    + service.metadata.withLabels({ 'magicentry.rs/enable': 'true' })
    + service.metadata.withAnnotations({
      'magicentry.rs/name': 'Hermes',
      'magicentry.rs/url': 'https://' + domain,
      'magicentry.rs/realms': 'admin',
      'magicentry.rs/oidc_redirect_urls': 'https://%s/auth/callback' % domain,
    }),

  dashboardRoute:
    httpRoute.new('hermes-dashboard')
    + httpRoute.metadata.withAnnotations({ 'cert-manager.io/cluster-issuer': 'letsencrypt' })
    + httpRoute.spec.withHostnames([domain])
    + httpRoute.spec.withParentRefs([{ name: 'traefik-gateway', namespace: 'traefik', sectionName: 'websecure-vpn' }])
    + httpRoute.spec.withRules([{
      backendRefs: [{ name: 'dashboard', port: dashboardPort }],
      matches: [{ path: { type: 'PathPrefix', value: '/' } }],
    }]),
}
