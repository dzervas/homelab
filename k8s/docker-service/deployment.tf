resource "kubernetes_deployment_v1" "docker" {
  count = var.type == "deployment" ? 1 : 0

  metadata {
    name      = var.name
    namespace = local.namespace
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    replicas = var.replicas

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
          for_each = var.pvs
          content {
            name = volume.value.name
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim_v1.docker[volume.key].metadata[0].name
              read_only  = volume.value.read_only
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
  }

  depends_on = [kubernetes_namespace.docker, kubernetes_persistent_volume_claim_v1.docker]
}
