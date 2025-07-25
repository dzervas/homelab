resource "kubernetes_service_v1" "docker" {
  count = var.metrics_port != 0 ? 1 : 0

  metadata {
    name      = "${var.name}-metrics"
    namespace = local.namespace
    labels = {
      managed_by = "terraform"
      service    = "${var.name}-metrics"
    }
  }

  spec {
    selector = local.selector

    port {
      port        = var.metrics_port
      target_port = var.metrics_port
    }
  }
}
