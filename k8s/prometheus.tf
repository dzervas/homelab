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
      }
    }
  })]
}

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
      name     = "metrics"
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
    type = "ClusterIP"
    port {
      name        = "metrics"
      protocol    = "TCP"
      port        = 9100
      target_port = 9100
    }
  }
}

resource "kubernetes_manifest" "prometheus_modem_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "modem-monitor"
      namespace = "prometheus"
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app        = "modem-node-exporter"
          managed_by = "terraform"
        }
      }
      endpoints = [
        {
          port     = 9100
          interval = "30s"
          path     = "/metrics"
        }
      ]
    }
  }
}
