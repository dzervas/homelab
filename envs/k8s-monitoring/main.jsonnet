local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'k8s-monitoring';
local cloudSecret = 'k8s-monitoring-op';

{
  namespace: k.core.v1.namespace.new(namespace),

  // Expected 1Password fields:
  // grafana_cloud_policy_username, grafana_cloud_policy_token.
  k8sMonitoringOp: opsecretLib.new('k8s-monitoring'),

  k8sMonitoring: helm.template('k8s-monitoring', '../../charts/k8s-monitoring', {
    namespace: namespace,
    values: {
      cluster: { name: 'homelab' },
      // prometheusOperatorObjects: { enabled: true },

      collectorCommon: {
        alloy: {
          remoteConfig: {
            enabled: true,
            url: 'https://fleet-management-prod-011.grafana.net',
            secret: {
              create: false,
              name: cloudSecret,
            },
            auth: {
              type: 'basic',
              usernameKey: 'grafana_cloud_policy_username',
              passwordKey: 'grafana_cloud_policy_token',
            },
          },
        },
      },

      collectors: {
        'alloy-metrics': {
          presets: ['small', 'deployment', 'clustered', 'service-discovery'],
          // presets: ['large', 'root', 'host-network', 'host-storage', 'host-cgroup', 'clustered', 'service-discovery', 'filesystem-log-reader', 'deployment'],
          alloy: {
            resources: {
              requests: { cpu: '50m', memory: '128Mi' },
              limits: { cpu: '300m', memory: '384Mi' },
            },
          },
          controller: { replicas: 2 },
        },

        // A DaemonSet is required to read each node's container log files.
        'alloy-logs': {
          presets: ['small', 'filesystem-log-reader', 'daemonset'],
          alloy: {
            resources: {
              requests: { cpu: '20m', memory: '64Mi' },
              limits: { cpu: '200m', memory: '256Mi' },
            },
          },
        },
      },

      telemetryServices: {
        'kube-state-metrics': {
          deploy: true,
          resources: {
            requests: { cpu: '10m', memory: '32Mi' },
            limits: { cpu: '100m', memory: '128Mi' },
          },
        },
      },

      'alloy-operator': {
        resources: {
          requests: { cpu: '10m', memory: '64Mi' },
          limits: { cpu: '500m', memory: '128Mi' },
        },
        // Helm hooks only; Tanka applies them as plain manifests, so the
        // pre-delete Job would tear down the Alloy CRs on every apply.
        waitForAlloyRemoval: { enabled: false },
      },
    },
  }),

  // Prometheus CRDs (needed for ServiceMonitor scraping compatibility)
  prometheusCrds: helm.template('prometheus-crds', '../../charts/prometheus-operator-crds', {
    namespace: namespace,
  }),
}
