resource "kubernetes_stateful_set" "docker" {
  count = var.type == "statefulset" ? 1 : 0

  metadata {
    name      = var.name
    namespace = kubernetes_namespace.docker.metadata[0].name
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    replicas     = var.replicas
    service_name = var.name

    selector {
      match_labels = {
        managed_by = "terraform"
        service    = var.name
      }
    }

    template {
      metadata {
        labels = {
          managed_by = "terraform"
          service    = var.name
        }
      }

      spec {
        container {
          name  = var.name
          image = var.image
          args  = var.args

          port {
            container_port = var.port
          }

          dynamic "volume_mount" {
            for_each = var.config_maps
            content {
              name       = volume_mount.value
              mount_path = volume_mount.key
              read_only  = true
            }
          }

          dynamic "volume_mount" {
            for_each = var.pvcs
            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.key
              read_only  = volume_mount.value.read_only
            }
          }
        }

        dynamic "volume" {
          for_each = var.config_maps
          content {
            name = volume.value
            config_map {
              name = volume.value
            }
          }
        }
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = var.retain_pvcs ? "Retain" : "Delete"
      when_scaled  = var.retain_pvcs ? "Retain" : "Delete"
    }
    dynamic "volume_claim_template" {
      for_each = var.pvcs

      content {
        metadata {
          name      = volume_claim_template.value.name
          namespace = kubernetes_namespace.docker.metadata[0].name
          labels = {
            managed_by = "terraform"
            service    = var.name
          }
        }

        spec {
          access_modes = volume_claim_template.value.access_modes
          resources {
            requests = {
              storage = volume_claim_template.value.size
            }
          }
        }
      }
    }
  }
}
