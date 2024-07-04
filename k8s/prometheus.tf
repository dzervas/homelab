resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "61.1.1"
  atomic           = true
  create_namespace = true

  values = [yamlencode({
    grafana      = { enabled = false }
    alertmanager = { enabled = false }
    prometheus = {
      prometheusSpec = {
        scrapeInterval                          = "30s"
        evaluationInterval                      = "30s"
        podMonitorSelectorNilUsesHelmValues     = false
        serviceMonitorSelectorNilUsesHelmValues = false
        # additionalScrapeConfigs = [{
        #   job_name = "modem-prometheus"
        #   static_configs = [{
        #     targets = ["10.11.12.1:9090"]
        #   }]
        # }]
      }
    }
  })]
}

resource "kubernetes_manifest" "modem_node_exporter" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "ScrapeConfig"
    metadata = {
      name      = "modem-node-exporter"
      namespace = "prometheus"
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      metricsPath = "/metrics"
      staticConfigs = [{
        labels = {
          device = "modem"
        }
        targets = ["10.11.12.1:9100"]
      }]
    }
  }
}

# resource "kubernetes_manifest" "modem_prometheus" {
#   manifest = {
#     apiVersion = "monitoring.coreos.com/v1"
#     kind       = "Prometheus"
#     metadata = {
#       name      = "modem-prometheus"
#       namespace = "prometheus"
#       labels = {
#         prometheus = "modem"
#         managed_by = "terraform"
#       }
#     }
#     spec = {
#       replicas = 1
#       serviceAccountName = "prometheus"
#       serviceMonitorSelector = {
#         matchLabels = {
#           app        = "modem-node-exporter"
#           managed_by = "terraform"
#         }
#       }
#       additionalScrapeConfigs
#     }
#   }
# }

# resource "kubernetes_secret_v1" "modem_prometheus" {
#   metadata {
#     name      = "modem-prometheus"
#     namespace = "prometheus"
#     labels = {
#       managed_by = "terraform"
#     }
#   }

#   data = {
#     modem_node_exporter = yamlencode([
#       {
#         job_name = "modem-prometheus"
#         static_configs = [{
#           targets = ["10.11.12.1:9090"]
#         }]
#       }
#     ])
#   }
# }

resource "kubernetes_endpoints_v1" "modem_node_exporter" {
  metadata {
    name      = "modem-node-exporter"
    namespace = "prometheus"
    labels = {
      app        = "modem-node-exporter"
      managed_by = "terraform"
    }
  }

  subset {
    address {
      ip = "10.11.12.1"
    }
    port {
      name     = "http-metrics"
      port     = 9100
      protocol = "TCP"
    }
  }
}

resource "kubernetes_service_v1" "modem_node_exporter" {
  metadata {
    name      = "modem-node-exporter"
    namespace = "prometheus"
    labels = {
      app        = "modem-node-exporter"
      managed_by = "terraform"
    }
  }

  spec {
    # type          = "ExternalName"
    # external_name = "10.11.12.1"
    selector = {
      app        = "modem-node-exporter"
      managed_by = "terraform"
    }
    port {
      name        = "http-metrics"
      protocol    = "TCP"
      port        = 9100
      target_port = 9100
    }
  }
}

# resource "kubernetes_manifest" "prometheus_modem_monitor" {
#   manifest = {
#     apiVersion = "monitoring.coreos.com/v1"
#     kind       = "ServiceMonitor"
#     metadata = {
#       name      = "modem-monitor"
#       namespace = "prometheus"
#       labels = {
#         managed_by = "terraform"
#       }
#     }
#     spec = {
#       selector = {
#         matchLabels = {
#           app        = "modem-node-exporter"
#           managed_by = "terraform"
#         }
#       }
#       endpoints = [
#         {
#           port     = 9100
#           interval = "30s"
#           path     = "/metrics"
#         }
#       ]
#     }
#   }
# }
