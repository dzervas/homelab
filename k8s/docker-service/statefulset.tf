resource "kubernetes_stateful_set" "docker" {
  count = var.type == "statefulset" ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
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
        node_selector = var.node_selector

        container {
          name    = var.name
          image   = var.image
          command = var.command
          args    = var.args

          port {
            container_port = var.port
          }

          dynamic "env" {
            for_each = var.env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "volume_mount" {
            for_each = merge(var.config_maps, var.secrets)
            content {
              name       = split(":", volume_mount.value)[0]
              mount_path = volume_mount.key
              read_only  = !endswith(volume_mount.value, ":rw")
            }
          }

          dynamic "volume_mount" {
            for_each = var.pvs
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
            name = split(":", volume.value)[0]
            config_map {
              name = split(":", volume.value)[0]
            }
          }
        }

        dynamic "volume" {
          for_each = var.secrets
          content {
            name = split(":", volume.value)[0]
            secret {
              secret_name = split(":", volume.value)[0]
            }
          }
        }
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = var.retain_pvs ? "Retain" : "Delete"
      when_scaled  = var.retain_pvs ? "Retain" : "Delete"
    }
    dynamic "volume_claim_template" {
      for_each = var.pvs

      content {
        metadata {
          name      = volume_claim_template.value.name
          namespace = local.namespace
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

  depends_on = [kubernetes_namespace.docker]
}
