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

// $HERMES_HOME/.local/bin is on the image's PATH and on the PV. `op update`
// only downloads the release zip, so both paths end in the same extraction.
// python3 is always in the image, curl/unzip may not be
local installOp = |||
  bin="$HERMES_HOME/.local/bin"
  dl=/tmp/op-download
  mkdir -p "$bin" "$dl"
  if [ -x "$bin/op" ]; then
    yes | "$bin/op" update --directory "$dl" || echo "op update failed, keeping $("$bin/op" --version)"
  else
    python3 - "$dl" <<'EOF'
  import json, platform, sys, urllib.request
  v = json.load(urllib.request.urlopen("https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N"))["version"]
  arch = {"aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
  urllib.request.urlretrieve(f"https://cache.agilebits.com/dist/1P/op2/pkg/v{v}/op_linux_{arch}_v{v}.zip", f"{sys.argv[1]}/op.zip")
  EOF
  fi
  for zip in "$dl"/*.zip; do
    [ -e "$zip" ] || continue
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("op", sys.argv[2])' "$zip" "$bin"
  done
  chmod +x "$bin/op"
  "$bin/op" --version
|||;

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

  // 1Password item fields: TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USERS,
  // TELEGRAM_GROUP_ALLOWED_CHATS
  secret:
    externalSecret.new('hermes-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'hermes-agent' } }]),

  // The operator runs `gateway run` (Telegram) and the image's s6 brings up the
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
            model: {
              provider: 'custom',
              base_url: 'http://cliproxyapi.cliproxyapi.svc:8317/v1',
              api_key: 'sk-dummy',
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
          },
        },
        storage: { persistence: { enabled: true } },
        // The operator sets no fsGroup and init-hermes runs as 10000, so the fresh PV
        // stays root-owned without this
        initChownData: true,
        env: [
          { name: 'HERMES_DASHBOARD', value: '1' },
          { name: 'TZ', value: timezone },
          {
            // Created manually, not managed by this env
            // kubectl -n hermes-agent create secret generic personal-op-service-account --from-literal=OP_SERVICE_ACCOUNT_TOKEN=(op read 'op://Private/v6n2l2au4ye3q6eh6ohwhfdjga/credential')
            name: 'OP_SERVICE_ACCOUNT_TOKEN',
            valueFrom: { secretKeyRef: { name: 'personal-op-service-account', key: 'OP_SERVICE_ACCOUNT_TOKEN' } },
          },
        ],
        envFrom: [{ secretRef: { name: 'hermes-op' } }],
        skills: [{ identifier: 'official/security/1password' }],
        initScripts: [{ name: 'install-op', script: installOp }],
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
