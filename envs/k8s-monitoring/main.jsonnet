local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local namespace = 'k8s-monitoring';
local cloudSecret = 'k8s-monitoring-op';

local cloudDestination(type, envPrefix) = {
  type: type,
  urlFrom: 'sys.env("%s_URL")' % envPrefix,
  auth: {
    type: 'basic',
    usernameFrom: 'sys.env("%s_USERNAME")' % envPrefix,
    passwordFrom: 'sys.env("%s_PASSWORD")' % envPrefix,
  },
  // Credentials are injected from the ExternalSecret, not rendered by Helm.
  secret: { embed: true },
};

local cloudEnv(name, key) = {
  name: name,
  valueFrom: { secretKeyRef: { name: cloudSecret, key: key } },
};

{
  namespace: k.core.v1.namespace.new(namespace),

  // Expected 1Password fields:
  // metrics-url, metrics-username, metrics-password,
  // logs-url, logs-username, logs-password.
  k8sMonitoringOp: opsecretLib.new('k8s-monitoring'),

  k8sMonitoring: helm.template('k8s-monitoring', '../../charts/k8s-monitoring', {
    namespace: namespace,
    values: {
      cluster: { name: 'gr' },

      destinations: {
        grafanaCloudMetrics: cloudDestination('prometheus', 'GRAFANA_CLOUD_METRICS'),
        grafanaCloudLogs: cloudDestination('loki', 'GRAFANA_CLOUD_LOGS'),
      },

      collectorCommon: {
        alloy: {
          extraEnv: [
            cloudEnv('GRAFANA_CLOUD_METRICS_URL', 'metrics-url'),
            cloudEnv('GRAFANA_CLOUD_METRICS_USERNAME', 'metrics-username'),
            cloudEnv('GRAFANA_CLOUD_METRICS_PASSWORD', 'metrics-password'),
            cloudEnv('GRAFANA_CLOUD_LOGS_URL', 'logs-url'),
            cloudEnv('GRAFANA_CLOUD_LOGS_USERNAME', 'logs-username'),
            cloudEnv('GRAFANA_CLOUD_LOGS_PASSWORD', 'logs-password'),
          ],
        },
      },

      // Keep the useful kube-prometheus-style sources while retaining Grafana's
      // default metric allow-lists to control Grafana Cloud usage.
      clusterMetrics: {
        enabled: true,
        collector: 'alloy-metrics',
        apiServer: { enabled: true },
        kubeDNS: { enabled: true },
        kubeProxy: { enabled: true },
      },

      // Continue scraping existing ServiceMonitor, PodMonitor, and Probe objects.
      prometheusOperatorObjects: {
        enabled: true,
        collector: 'alloy-metrics',
      },

      podLogsViaLoki: {
        enabled: true,
        collector: 'alloy-logs',
      },

      clusterEvents: {
        enabled: true,
        collector: 'alloy-metrics',
      },

      collectors: {
        'alloy-metrics': {
          presets: ['small', 'deployment'],
          alloy: {
            resources: {
              requests: { cpu: '50m', memory: '128Mi' },
              limits: { cpu: '300m', memory: '384Mi' },
            },
          },
          controller: { replicas: 1 },

          // Preserve the NixOS node-exporter and smartctl-exporter scrapes from
          // the VictoriaMetrics setup without deploying duplicate exporters.
          extraConfig: |||
            discovery.kubernetes "nixos_nodes" {
              role = "node"
            }

            discovery.relabel "nixos_node_exporter" {
              targets = discovery.kubernetes.nixos_nodes.targets

              rule {
                source_labels = ["__meta_kubernetes_node_address_InternalIP"]
                regex         = "(.+)"
                target_label  = "__address__"
                replacement   = "$1:9100"
              }

              rule {
                source_labels = ["__meta_kubernetes_node_name"]
                target_label  = "instance"
              }
            }

            prometheus.scrape "nixos_node_exporter" {
              targets         = discovery.relabel.nixos_node_exporter.output
              job_name        = "nixos-node-exporter"
              scrape_interval = "30s"
              forward_to      = [prometheus.relabel.nixos_node_exporter.receiver]
            }

            prometheus.relabel "nixos_node_exporter" {
              rule {
                source_labels = ["mountpoint"]
                regex         = "/var/lib/kubelet/pods.+"
                action        = "drop"
              }

              forward_to = [prometheus.remote_write.grafanacloudmetrics.receiver]
            }

            discovery.relabel "nixos_smartctl_exporter" {
              targets = discovery.kubernetes.nixos_nodes.targets

              rule {
                source_labels = ["__meta_kubernetes_node_address_InternalIP"]
                regex         = "(.+)"
                target_label  = "__address__"
                replacement   = "$1:9633"
              }

              rule {
                source_labels = ["__meta_kubernetes_node_name"]
                target_label  = "instance"
              }
            }

            prometheus.scrape "nixos_smartctl_exporter" {
              targets         = discovery.relabel.nixos_smartctl_exporter.output
              job_name        = "nixos-smartctl-exporter"
              scrape_interval = "60s"
              forward_to      = [prometheus.remote_write.grafanacloudmetrics.receiver]
            }
          |||,
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
          limits: { cpu: '200m', memory: '128Mi' },
        },
        waitForAlloyRemoval: {
          resources: {
            requests: { cpu: '5m', memory: '32Mi' },
            limits: { cpu: '100m', memory: '64Mi' },
          },
        },
      },
    },
  }),
}
