resource "kubernetes_service" "docker" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.docker.metadata.0.name
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    selector = var.type == "deployment" ? kubernetes_deployment.docker.0.spec[0].selector[0].match_labels : kubernetes_stateful_set.docker.0.spec.0.selector.0.match_labels

    port {
      port        = var.port
      target_port = var.port
    }
  }
}
