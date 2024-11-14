resource "kubernetes_service" "docker" {
  metadata {
    name      = var.name
    namespace = local.namespace
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    selector = var.type == "deployment" ? kubernetes_deployment_v1.docker.0.spec[0].selector[0].match_labels : kubernetes_stateful_set.docker.0.spec.0.selector.0.match_labels

    port {
      port        = var.port
      target_port = var.port
    }
  }
}
