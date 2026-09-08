local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'k8s-monitoring';
local cloudSecret = 'k8s-monitoring-op';
local cloudEnv = [
  {
    name: 'GCLOUD_FM_USERNAME',
    valueFrom: { secretKeyRef: { name: cloudSecret, key: 'grafana_cloud_policy_username' } },
  },
  {
    name: 'GCLOUD_RW_API_KEY',
    valueFrom: { secretKeyRef: { name: cloudSecret, key: 'grafana_cloud_policy_token' } },
  },
];

{
  namespace: k.core.v1.namespace.new(namespace),

  // Expected 1Password fields:
  // grafana_cloud_policy_username, grafana_cloud_policy_token.
  k8sMonitoringOp: opsecretLib.new('k8s-monitoring'),

  k8sMonitoring: helm.template('k8s-monitoring', '../../charts/k8s-monitoring', {
    namespace: namespace,
    values: {
      cluster: { name: 'homelab' },

      collectorCommon: {
        alloy: {
          remoteConfig: {
            enabled: true,
            url: 'https://fleet-management-prod-011.grafana.net',
            auth: {
              type: 'basic',
              usernameFrom: 'sys.env("GCLOUD_FM_USERNAME")',
              passwordFrom: 'sys.env("GCLOUD_RW_API_KEY")',
            },
          },
        },
      },

      collectors: {
        'alloy-metrics': {
          presets: ['small', 'deployment', 'clustered', 'service-discovery'],
          // presets: ['large', 'root', 'host-network', 'host-storage', 'host-cgroup', 'clustered', 'service-discovery', 'filesystem-log-reader', 'deployment'],
          alloy: {
            extraEnv: cloudEnv,
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
          // The 'daemonset' preset sets a keyless `effect: NoSchedule, operator: Exists`
          // toleration, which swallows the storage-only taint on gr1. Narrow it to the
          // standard DaemonSet taints so tainted nodes are actually respected.
          controller: {
            tolerations: [
              { key: 'node.kubernetes.io/disk-pressure', operator: 'Exists', effect: 'NoSchedule' },
              { key: 'node.kubernetes.io/memory-pressure', operator: 'Exists', effect: 'NoSchedule' },
              { key: 'node.kubernetes.io/pid-pressure', operator: 'Exists', effect: 'NoSchedule' },
              { key: 'node.kubernetes.io/unschedulable', operator: 'Exists', effect: 'NoSchedule' },
            ],
          },
          alloy: {
            extraEnv: cloudEnv,
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
          limits: { cpu: '200m', memory: '128Mi' },
        },
        // Helm hooks only; Tanka applies them as plain manifests, so the
        // pre-delete Job would tear down the Alloy CRs on every apply.
        waitForAlloyRemoval: { enabled: false },
      },
    },
  }),
}
