resource "random_password" "n8n_encryption_key" {
  length = 40
}
module "n8n" {
  source = "./docker-service"

  type             = "statefulset"
  name             = "n8n"
  fqdn             = "auto.${var.domain}"
  create_namespace = true
  ingress_enabled  = true
  auth             = "mtls"
  vpn_bypass_auth  = true
  vpn_cidrs        = var.vpn_cidrs
  image            = "ghcr.io/n8n-io/n8n:1.71.3"
  port             = 5678
  retain_pvs       = true
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "16m" # Also defined with env N8N_PAYLOAD_SIZE_MAX
  }
  pvs = {
    "/home/node/.n8n" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }
  env = {
    TZ                                    = var.timezone
    GENERIC_TIMEZONE                      = var.timezone
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = true
    DB_SQLITE_VACUUM_ON_STARTUP           = true
    N8N_EDITOR_BASE_URL                   = "auto.${var.domain}"
    WEBHOOK_URL                           = "hook.${var.domain}"
    N8N_ENCRYPTION_KEY                    = random_password.n8n_encryption_key.result
    N8N_PROXY_HOPS                        = 1 # Allows X-Forwarded-For header
    N8N_PORT                              = "5678"

    EXECUTIONS_DATA_PRUNE           = true
    EXECUTIONS_DATA_MAX_AGE         = 168 # 1 week
    EXECUTIONS_DATA_PRUNE_MAX_COUNT = 50000
    DB_SQLITE_VACUUM_ON_STARTUP     = true

    # TODO: Add prometheus metrics
    # N8N_METRICS                           = true
    # TODO: S3 storage
    # N8N_EXTERNAL_STORAGE_S3_HOST = "whatever"
  }
}

resource "kubernetes_ingress_v1" "n8n_webhooks" {
  metadata {
    name      = "n8n-webhooks"
    namespace = module.n8n.namespace
    annotations = {
      "cert-manager.io/cluster-issuer"           = "letsencrypt"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
    }
    labels = {
      managed_by = "terraform"
      service    = "n8n"
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = "hook.${var.domain}"
      http {
        dynamic "path" {
          for_each = ["/webhook/", "/webhook-test/", "/webhook-waiting/"]
          content {
            path      = path.value
            path_type = "Prefix"
            backend {
              service {
                name = "n8n"
                port {
                  number = 5678
                }
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = ["hook.${var.domain}"]
      secret_name = "${replace("hook.${var.domain}", ".", "-")}-webhook-cert"
    }
  }
}

# Required to manually edit the statefulset to add above the "containers" key:
# initContainers:
# - name: init-permissions
#   image: busybox
#   command: ["sh", "-c", "chown 1000:1000 /mnt/data"]
#   volumeMounts:
#   - name: data
#     mountPath: /mnt/data
# Should be required only once to fix the permissions on the persistent volume.
