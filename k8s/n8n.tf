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
  image            = "ghcr.io/n8n-io/n8n:1.68.1"
  port             = 5678
  retain_pvs       = true
  svc_annotations = {
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

    # TODO: Add prometheus metrics
    # N8N_METRICS                           = true
    # TODO: S3 storage
    # N8N_EXTERNAL_STORAGE_S3_HOST = "whatever"
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
