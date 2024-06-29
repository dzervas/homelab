resource "kubernetes_namespace" "docker" {
  metadata {
    name = var.name
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }
}
