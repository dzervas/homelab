resource "kubernetes_persistent_volume_claim_v1" "docker" {
  for_each = var.type == "deployment" ? var.pvs : {}

  metadata {
    name      = each.value.name
    namespace = local.namespace
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    access_modes = each.value.access_modes
    resources {
      requests = {
        storage = each.value.size
      }
    }
  }
}
