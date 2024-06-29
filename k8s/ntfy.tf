resource "kubernetes_namespace" "ntfy" {
  metadata {
    name = "ntfy"
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "kubernetes_config_map" "ntfy_config" {
  metadata {
    name      = "ntfy"
    namespace = kubernetes_namespace.ntfy.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  data = {
    "server.yml" = yamlencode({
      base-url            = "https://ntfy.${var.domain}"
      upstream-base-url   = "https://ntfy.sh"
      behind-proxy        = true
      auth-default-access = "deny-all"
      auth-file           = "/var/lib/ntfy/user.db"
      cache-file          = "/var/lib/ntfy/cache.db"
    })
  }
}

resource "kubernetes_service" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = kubernetes_namespace.ntfy.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  spec {
    selector = kubernetes_stateful_set.ntfy.spec[0].selector[0].match_labels

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_stateful_set" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = kubernetes_namespace.ntfy.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  spec {
    replicas     = 1
    service_name = "ntfy"

    selector {
      match_labels = {
        app = "ntfy"
      }
    }

    template {
      metadata {
        labels = {
          app        = "ntfy"
          managed_by = "terraform"
        }
      }

      spec {
        container {
          name  = "ntfy"
          image = "binwiederhier/ntfy:latest"
          args  = ["serve"]

          port {
            container_port = 80
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/ntfy"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/ntfy"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map.ntfy_config.metadata[0].name
          }
        }
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }
    volume_claim_template {
      metadata {
        name      = "data"
        namespace = kubernetes_namespace.ntfy.metadata[0].name
        labels = {
          managed_by = "terraform"
        }
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}
