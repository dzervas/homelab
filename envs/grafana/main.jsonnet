local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);
local k = import 'k.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local gemini = import 'helpers/gemini.libsonnet';
local opsecretLib = import 'docker-service/opsecret.libsonnet';

local namespace = 'grafana';
local domain = 'vpn.dzerv.art';
local grafanaFqdn = 'grafana.' + domain;
local mcpFqdn = 'mcp.' + grafanaFqdn;

{
  namespace: k.core.v1.namespace.new(namespace),

  grafana: helm.template('grafana', '../../charts/grafana', {
    namespace: namespace,
    values: {
      testFramework: { enabled: false },
      useStatefulSet: true,  // OpenEBS doesn't support RWX

      persistence: {
        enabled: true,
        storageClassName: 'openebs-replicated',
      },

      ingress: ingress.hostList(grafanaFqdn, ingress.vpnAnnotations(namespace) {
        'nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream': 'true',
      }),
      networkPolicy: { enabled: true },

      plugins: [
        'grafana-llm-app',
        'victoriametrics-logs-datasource',
        'victoriametrics-metrics-datasource',
      ],
      imageRenderer: {
        enabled: true,
        // Fixes a bug with the resulting URL returned to the UI
        renderingCallbackURL: 'http://grafana',
      },

      'grafana.ini': {
        users: { allow_sign_up: false },
        server: { root_url: 'https://' + grafanaFqdn },
        database: {
          // Database locked workarounds: https://github.com/grafana/grafana/issues/68941#issuecomment-1567941013
          wal: true,
          query_retires: 3,
          transaction_retries: 5,
        },
      },

      datasources: {
        'datasources.yaml': {
          apiVersion: 1,
          datasources: [
            {
              name: 'VictoriaLogs',
              type: 'victoriametrics-logs-datasource',
              url: 'http://vlsingle-victorialogs-server.victorialogs.svc:9428',
            },
          ],
        },
      },

      nodeSelector: {
        provider: 'oracle',
      },

      rbac: {
        useExistingClusterRole: 'grafana',
      },

      // Allow arbitrary services to create grafana resources through a configmap
      sidecar: {
        enableUniqueFilenames: true,  // Avoid overwrites due to same filenames

        // Needs label `grafana_alert=1`
        alerts: {
          enabled: true,
          resource: 'configmap',
          searchNamespace: 'ALL',
        },

        // Needs label `grafana_dashboard=1`
        dashboards: {
          enabled: true,
          resource: 'configmap',
          searchNamespace: 'ALL',
          defaultFolderName: 'collected',  // target subdirectory in the PV
          // grafana_folder annotation can describe the target folder (within grafana)
          folderAnnotation: 'grafana_folder',
          // Place all collected dashboards under this folder
          provider: { folder: 'Collected' },
        },

        // Needs label `grafana_datasource=1`
        datasources: {
          enabled: true,
          resource: 'configmap',
          searchNamespace: 'ALL',
        },

        // Needs label `grafana_notifier=1`
        notifiers: {
          enabled: true,
          resource: 'configmap',
          searchNamespace: 'ALL',
        },
      },

      admin: {
        existingSecret: 'grafana-op',
        userKey: 'username',
        passwordKey: 'password',
      },
    },
  }),
  grafanaOp: opsecretLib.new('grafana'),

  // Define our own cluster role since by default it has access to all secrets too
  grafanaClusterRole:
    k.rbac.v1.clusterRole.new('grafana')
    + k.rbac.v1.clusterRole.withRules([{
      apiGroups: [''],
      resources: ['configmaps'],
      verbs: ['get', 'list', 'watch'],
    }]),

  grafanaBackup: gemini.backup('grafana', 'storage-grafana-0', [
    { every: 'day', keep: 3 },
    { every: 'week', keep: 4 },
    { every: 'month', keep: 1 },
  ]),

  // Grafana MCP server
  grafanaMcp: helm.template('grafana-mcp', '../../charts/grafana-mcp', {
    namespace: namespace,
    values: {
      extraArgs: ['--transport', 'streamable-http'],
      grafana: {
        url: 'http://grafana',
        apiKeySecret: {
          name: 'grafana-mcp-op',
          key: 'sa-token',
        },
      },
    },
  }),

  grafanaMcpOp: opsecretLib.new('grafana-mcp'),

  // Network policy to allow n8n access to grafana-mcp
  grafanaMcpN8nAccessNetworkPolicy:
    k.networking.v1.networkPolicy.new('grafana-mcp-n8n-access')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/component': 'mcp-server',
      'app.kubernetes.io/instance': 'grafana-mcp',
      'app.kubernetes.io/name': 'grafana-mcp',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: [{
        namespaceSelector: {
          matchLabels: {
            'kubernetes.io/metadata.name': 'n8n',
          },
        },
      }],
    }]),
}
