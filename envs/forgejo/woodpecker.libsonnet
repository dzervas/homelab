local workers = import './woodpecker/agent.libsonnet';
local policy = import './woodpecker/policy.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local helm = tk.helm.new(std.thisFile);

local password = externalSecrets.generators.v1alpha1.password;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local grpcSecretName = 'woodpecker-grpc-secret';

{
  woodpecker:
    helm.template('woodpecker', '../../charts/woodpecker', {
      namespace: 'forgejo',
      values: {
        fullnameOverride: 'woodpecker',
        agent: { enabled: false },
        server: {
          networkPolicy: {
            enabled: true,
            ingress: {
              http: [{
                podSelector: { matchLabels: { app: 'forgejo' } },
              }],
            },
            egress: {
              extra: [
                {
                  ports: [{ port: 80, protocol: 'TCP' }],
                  to: [{
                    podSelector: { matchLabels: { app: 'forgejo' } },
                  }],
                },
                {
                  ports: [{ port: 10443, protocol: 'TCP' }],
                  to: [{
                    namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
                    podSelector: { matchLabels: {
                      'app.kubernetes.io/instance': 'traefik-traefik',
                      'app.kubernetes.io/name': 'traefik',
                    } },
                  }],
                },
              ],
            },
          },
          ingress: ingress.hostObj('ci.vpn.dzerv.art'),
          createAgentSecret: false,
          extraSecretNamesForEnvFrom: [
            'woodpecker-agent-op',
            'woodpecker-server-op',
            grpcSecretName,
          ],
          env: {
            WOODPECKER_HOST: 'https://ci.vpn.dzerv.art',
            WOODPECKER_OPEN: 'false',
            WOODPECKER_ADMIN: 'dzervas',
            WOODPECKER_AUTHENTICATE_PUBLIC_REPOS: 'true',

            WOODPECKER_FORGEJO: 'true',
            WOODPECKER_FORGEJO_URL: 'http://forgejo',
            WOODPECKER_EXPERT_FORGE_OAUTH_HOST: 'https://git.vpn.dzerv.art',
            WOODPECKER_FORCE_IGNORE_SERVICE_FAILURE: 'false',

            WOODPECKER_EXPERT_WEBHOOK_HOST: 'http://woodpecker-server',

            // Stock SQLite uses a rollback journal and a 5s busy timeout, so log writes on
            // Longhorn locked out other queries; WAL lets readers run alongside the writer
            WOODPECKER_DATABASE_DATASOURCE: '/var/lib/woodpecker/woodpecker.sqlite?_journal_mode=WAL&_busy_timeout=30000&_txlock=immediate',
            // Pipeline logs were the bulk of the DB writes
            WOODPECKER_LOG_STORE: 'file',
            WOODPECKER_LOG_STORE_FILE_PATH: '/var/lib/woodpecker/logs',

            TZ: timezone,
          },
        },
      },
    }),

  woodpeckerAgentSecret: opsecretLib.new('woodpecker-agent'),
  woodpeckerServerSecret: opsecretLib.new('woodpecker-server'),

  // Without a persisted secret the server generates a new one per restart
  woodpeckerGrpcSecretGenerator:
    password.new(grpcSecretName)
    + password.metadata.withNamespace('forgejo')
    + password.spec.withLength(64)
    + password.spec.withSymbols(0)
    + password.spec.withAllowRepeat(true),

  woodpeckerGrpcSecret:
    externalSecret.new(grpcSecretName)
    + externalSecret.metadata.withNamespace('forgejo')
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.target.withName(grpcSecretName)
    + externalSecret.spec.target.withCreationPolicy('Owner')
    + externalSecret.spec.target.template.withData({
      WOODPECKER_GRPC_SECRET: '{{ .password }}',
    })
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'Password',
          name: grpcSecretName,
        },
      },
    }]),

  // CiliumNetworkPolicy to allow agent egress to kube-apiserver.
  // Standard NetworkPolicy ipBlock CIDR rules don't match Cilium's
  // reserved kube-apiserver identity, so we need an explicit entity allow.
  woodpeckerAgentApiserverEgress: {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      name: 'woodpecker-agent-apiserver-egress',
      namespace: 'forgejo',
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'app.kubernetes.io/instance': 'woodpecker',
          'app.kubernetes.io/name': 'agent',
        },
      },
      egress: [
        { toEntities: ['kube-apiserver'] },
        {
          toEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'kube-system', 'k8s:k8s-app': 'kube-dns' } }],
          toPorts: [{ ports: [{ port: '53', protocol: 'ANY' }] }],
        },
        {
          toEndpoints: [{ matchLabels: {
            'k8s:io.kubernetes.pod.namespace': 'forgejo',
            'k8s:app.kubernetes.io/instance': 'woodpecker',
            'k8s:app.kubernetes.io/name': 'server',
          } }],
          toPorts: [{ ports: [{ port: '9000', protocol: 'TCP' }] }],
        },
      ],
    },
  },
} + workers + policy
