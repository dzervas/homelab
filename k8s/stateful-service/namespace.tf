resource "kubernetes_namespace" "stateful" {
  metadata {
    name = var.name
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "kubernetes_service" "stateful" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.stateful.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  spec {
    selector = kubernetes_stateful_set.ntfy.spec[0].selector[0]

    port {
      port        = 80
      target_port = 80
    }
  }
}
