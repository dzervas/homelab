locals {
  namespace = var.namespace != "" ? var.namespace : var.name
  ghcr = var.ghcr_image || startswith(var.image, "ghcr.io/dzervas/")
}


resource "kubernetes_namespace" "docker" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = local.namespace
    labels = {
      managed_by = "terraform"
      service    = var.name
      ghcrCreds  = local.ghcr ? "enabled" : "disabled"
    }
  }
}
