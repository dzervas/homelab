resource "kubernetes_deployment" "docker" {
  count = var.type == "deployment" ? 1 : 0

  metadata {
    name      = var.name
    namespace = kubernetes_namespace.docker.metadata[0].name
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
        container {
          name  = var.name
          image = var.image
          args  = var.args

          port {
            container_port = var.port
          }

          # TODO: Add volumes
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
      }
    }
  }
}
