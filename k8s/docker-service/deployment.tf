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
        labels = merge(
          {
            managed_by = "terraform"
            service    = var.name
          },
          var.magicentry_access ? { "magicentry.rs/enable" = "true" } : {},
          var.rclone_access ? { "rclone/enable" = "true" } : {},
          var.pod_labels
        )
      }

      spec {
        node_selector = var.node_selector
        dynamic "image_pull_secrets" {
          for_each = local.ghcr ? ["ghcr-cluster-secret"] : []
          content {
            name = image_pull_secrets.value
          }
        }

        dynamic "init_container" {
          for_each = var.init_containers
          content {
            name              = init_container.value.name
            image             = init_container.value.image
            command           = lookup(init_container.value, "command", [])
            args              = lookup(init_container.value, "args", [])
            image_pull_policy = (var.image_pull_policy || !strcontains(init_container.value.image, ":") || endswith(init_container.value.image, ":latest")) ? "Always" : "IfNotPresent"

            dynamic "env" {
              for_each = var.env_secrets
              content {
                name = env.key
                value_from {
                  secret_key_ref {
                    name = env.value.secret
                    key  = env.value.key
                  }
                }
              }
            }

            dynamic "env" {
              for_each = merge(lookup(init_container.value, "env", {}), var.env)
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
        }
        dynamic "security_context" {
          for_each = var.enable_security_context ? [1] : []
          content {
            run_as_non_root = true
            run_as_user     = var.run_as_user
            run_as_group    = var.run_as_user
            fs_group        = var.run_as_user
            seccomp_profile {
              type = "RuntimeDefault"
            }
          }
        }
        container {
          name              = var.name
          image             = var.image
          command           = var.command
          args              = var.args
          image_pull_policy = (var.image_pull_policy || !strcontains(var.image, ":") || endswith(var.image, ":latest")) ? "Always" : "IfNotPresent"

          port {
            container_port = var.port
          }

          dynamic "env" {
            for_each = var.env_secrets
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = env.value.secret
                  key  = env.value.key
                }
              }
            }
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

          dynamic "security_context" {
            for_each = var.enable_security_context ? [1] : []
            content {
              allow_privilege_escalation = false
              privileged                 = false
              run_as_non_root            = true
              run_as_user                = var.run_as_user
              run_as_group               = var.run_as_user
              capabilities {
                drop = ["ALL"]
              }
              seccomp_profile {
                type = "RuntimeDefault"
              }
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
