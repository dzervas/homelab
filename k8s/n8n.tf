# Required to manually edit the statefulset to add above the "containers" key:
# k edit statefulset.apps/n8n -n n8n
# initContainers:
# - name: init-permissions
#   image: busybox
#   command: ["sh", "-c", "chown 1000:1000 /mnt/data"]
#   volumeMounts:
#   - name: data
#     mountPath: /mnt/data
# Should be required only once to fix the permissions on the persistent volume.

# To benchmark:
# kubectl port-forward svc/n8n --address 0.0.0.0 8181:5678
# podman run --rm -it ghcr.io/n8n-io/n8n-benchmark:latest run --n8nBaseUrl=http://host.docker.internal:8181 --n8nUserEmail=dzervas@dzervas.gr --n8nUserPassword=$N8N_PASS --vus=5 --duration=5m

module "n8n" {
  source = "./docker-service"

  type             = "statefulset"
  name             = "n8n"
  fqdn             = "auto.${var.domain}"
  create_namespace = true
  ingress_enabled  = true
  auth             = "mtls"
  # vpn_bypass_auth  = true
  # vpn_cidrs        = var.vpn_cidrs
  image         = "ghcr.io/dzervas/n8n:latest"
  port          = 5678
  retain_pvs    = true
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
    "/home/node/backups" = {
      name         = "backups"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = false
    }
  }
  env = {
    TZ                                    = var.timezone
    GENERIC_TIMEZONE                      = var.timezone
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = true
    N8N_EDITOR_BASE_URL                   = "https://auto.${var.domain}"
    WEBHOOK_URL                           = "https://hook.${var.domain}"
    N8N_ENCRYPTION_KEY                    = local.op_secrets.n8n.encryption_key
    N8N_PROXY_HOPS                        = 1 # Allows X-Forwarded-For header
    N8N_PORT                              = "5678"
    N8N_DEFAULT_BINARY_DATA_MODE          = "filesystem"

    EXECUTIONS_TIMEOUT              = 600
    EXECUTIONS_DATA_PRUNE           = true
    EXECUTIONS_DATA_MAX_AGE         = 168 # 1 week
    EXECUTIONS_DATA_PRUNE_MAX_COUNT = 50000
    # DB_SQLITE_VACUUM_ON_STARTUP     = true # Makes startup painfully slow

    # TODO: Add prometheus metrics
    # N8N_METRICS                           = true
    # TODO: Requires https
    # N8N_EXTERNAL_STORAGE_S3_HOST          = "rclone.rclone.svc.cluster.local:8080"
    # N8N_EXTERNAL_STORAGE_S3_BUCKET_NAME   = "n8n"
    # N8N_EXTERNAL_STORAGE_S3_BUCKET_REGION = "auto"
    # N8N_EXTERNAL_STORAGE_S3_ACCESS_KEY    = random_password.rclone_access_key.result
    # N8N_EXTERNAL_STORAGE_S3_ACCESS_SECRET = random_password.rclone_secret_key.result
    # N8N_AVAILABLE_BINARY_DATA_MODES       = "filesystem,s3"
    # N8N_DEFAULT_BINARY_DATA_MODE          = "s3"

    # Disable diagnostics (https://docs.n8n.io/hosting/configuration/configuration-examples/isolation/)
    EXTERNAL_FRONTEND_HOOKS_URLS = ""
    N8N_DIAGNOSTICS_ENABLED = "false"
    N8N_DIAGNOSTICS_CONFIG_FRONTEND = ""
    N8N_DIAGNOSTICS_CONFIG_BACKEND = ""

    GLOBAL_VARS = jsonencode({
      browserless_host     = "n8n-browserless"
      browserless_port     = "3000"
      browserless_token    = random_password.n8n_browserless_token.result
      browserless_endpoint = "ws://n8n-browserless:3000/?token=${random_password.n8n_browserless_token.result}"
    })

    CREDENTIAL_OVERWRITE_DATA = jsonencode({
      browserlessApi = {
        url   = "http://n8n-browserless:3000",
        token = random_password.n8n_browserless_token.result
      }
    })
  }
}

resource "random_password" "n8n_browserless_token" {
  length  = 32
  special = false
}

module "n8n-browserless" {
  source = "./docker-service"

  type             = "deployment"
  name             = "n8n-browserless"
  namespace        = module.n8n.namespace
  create_namespace = false
  fqdn             = "browser.${var.domain}"
  ingress_enabled  = true
  # ingress_annotations = {
  #   "nginx.ingress.kubernetes.io/server-snippet" = <<EOF
  #     location = /debugger {
  #       if ($is_args = "") {
  #         return 301 /debugger/?token=${random_password.n8n_browserless_token.result};
  #       }
  #     }
  #   EOF
  # }
  auth          = "mtls"
  image         = "ghcr.io/browserless/chromium"
  port          = 3000
  node_selector = { "kubernetes.io/arch" = "amd64" }
  env = {
    ALLOW_GET  = true # Required for some stuff in the n8n node
    TOKEN      = random_password.n8n_browserless_token.result
    PROXY_HOST = "n8n-browserless.${module.n8n.namespace}.svc.cluster.local"
    PROXY_PORT = "3000"
    PROXY_SSL  = false
    CONCURRENT = 5
    QUEUED     = 10
  }
}

resource "kubernetes_ingress_v1" "n8n_webhooks" {
  metadata {
    name      = "n8n-webhooks"
    namespace = module.n8n.namespace
    annotations = {
      "cert-manager.io/cluster-issuer"              = "letsencrypt"
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "16m" # Also defined with env N8N_PAYLOAD_SIZE_MAX
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

data "kubernetes_persistent_volume_claim" "n8n_backup" {
  metadata {
    namespace = module.n8n.namespace
    name      = "backups-n8n-0"
    labels = {
      managed_by = "terraform"
      service    = "n8n"
    }
  }
}
