locals {
  pvs_nonemptydir = {for n, pv in var.pvs : n => pv if !pv.empty_dir}
  pvs_emptydir = {for n, pv in var.pvs : n => pv if pv.empty_dir}
}

resource "kubernetes_persistent_volume_claim_v1" "docker" {
  for_each = var.type == "deployment" ? local.pvs_nonemptydir : {}

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
