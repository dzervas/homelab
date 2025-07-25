resource "kubernetes_manifest" "docker_servicemonitor" {
  count = var.metrics_port != 0 ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "${var.name}-metrics"
      namespace = local.namespace
      labels = {
        managed_by = "terraform"
        service    = "${var.name}-metrics"
      }
    }

    spec = {
      selector = {
        matchLabels = kubernetes_service_v1.docker_metrics[0].metadata[0].labels
      }

      jobLabel = var.name
      endpoints = [{
        port     = "metrics"
        path     = var.metrics_path
        interval = var.metrics_interval
      }]
    }
  }
}
