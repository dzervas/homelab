local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local k = import 'k.libsonnet';
local vm = import 'victoria-metrics-operator-libsonnet/0.50/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'victoriametrics';

{
  namespace: k.core.v1.namespace.new(namespace),

  nodeExporterScrape:
    vm.operator.v1beta1.vmNodeScrape.new('nixos-node-exporter')
    + { metadata+: { namespace: namespace } }
    + {
      spec+: {
        scheme: 'http',
        port: '9100',
        path: '/metrics',
        interval: '30s',
        jobLabel: 'jobLabel',
        metricRelabelConfigs: [
          {
            action: 'drop',
            source_labels: ['mountpoint'],
            regex: '/var/lib/kubelet/pods.+',
          },
        ],
      },
    },

  smartctlExporterScrape:
    vm.operator.v1beta1.vmNodeScrape.new('nixos-smartctl-exporter')
    + { metadata+: { namespace: namespace } }
    + {
      spec+: {
        scheme: 'http',
        port: '9633',
        path: '/metrics',
        interval: '1m',
        jobLabel: 'jobLabel',
      },
    },

  victoriametrics:
    helm.template('victoriametrics', '../../charts/victoria-metrics-k8s-stack', {
      namespace: namespace,
      values: {
        fullnameOverride: 'victoriametrics',
        vmsingle: {
          spec: {
            extraArgs: { 'opentelemetry.usePrometheusNaming': 'true' },
            retentionPeriod: '8w',
            storage: {
              resources: {
                requests: { storage: '50Gi' },
              },
            },
            nodeSelector: { provider: 'oracle' },
          },

          ingress: ingress.hostList('metrics.vpn.dzerv.art'),
        },

        external: {
          grafana: {
            host: 'grafana.dzerv.art',
            datasource: 'Victoria',
          },
        },

        defaultDashboards: {
          enabled: true,
          // labels: { grafana_dashboard: '1' },
        },

        // TODO: The following listen at pod-localhost by default so we can't scrape them
        // TODO: Scrape RKE2 metrics too: https://docs.rke2.io/reference/metrics
        kubeEtcd: { enabled: false },
        kubeScheduler: { enabled: false },
        kubeControllerManager: { enabled: false },
        defaultRules: {
          groups: {
            etcd: { enabled: false },
            kubernetesSystemScheduler: { enabled: false },
            kubernetesSystemControllerManager: { enabled: false },
          },
        },
        // NixOS defined
        'prometheus-node-exporter': { enabled: false },
        // Has its own env
        grafana: {
          enabled: false,
          forceDeployDatasource: true,
        },

        'victoria-metrics-operator': {
          crds: { plain: false },  // Render the CRDs to be able to upgrade them
          admissionWebhooks: {
            certManager: {
              enabled: true,
            },
          },
        },
      },
    }),

  // Prometheus CRDs (needed for ServiceMonitor scraping compatibility)
  prometheusCrds: helm.template('prometheus-crds', '../../charts/prometheus-operator-crds', {
    namespace: namespace,
    values: {
      crds: {
        thanosrulers: { enabled: true },
      },
    },
  }),

  grafanaAccessNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-victoriametrics-grafana')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'managed-by': 'vm-operator',
      'app.kubernetes.io/name': 'vmsingle',
      'app.kubernetes.io/instance': 'victoriametrics',
      'app.kubernetes.io/component': 'monitoring',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'grafana' } } },
          { podSelector: { matchLabels: { 'app.kubernetes.io/name': 'grafana' } } },
        ],
      },
    ]),

  operatorWebhookNetworkPolicy:
    k.networking.v1.networkPolicy.new('victoriametrics-op-webhook')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/name': 'victoria-metrics-operator',
      'app.kubernetes.io/instance': 'victoriametrics',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([
      {
        from: [
          { namespaceSelector: {} },
          { podSelector: {} },
          { ipBlock: { cidr: '0.0.0.0/0' } },
        ],
        ports: [{ protocol: 'TCP', port: 9443 }],
      },
    ]),
}
