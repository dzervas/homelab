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
        container {
          name  = var.name
          image = var.image
          args  = var.args

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
            for_each = var.config_maps
            content {
              name       = volume_mount.value
              mount_path = volume_mount.key
              read_only  = true
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
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.docker]
}
