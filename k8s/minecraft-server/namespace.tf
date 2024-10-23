resource "kubernetes_namespace" "minecraft" {
  metadata {
    name = var.namespace
    labels = {
      managed_by = "terraform"
    }
  }
}
