# Required to manually edit the statefulset to add above the "containers" key:
# k edit deployment.apps/filestash -n files
# initContainers:
# - name: init-permissions
#   image: busybox
#   command: ["sh", "-c", "mkdir -p /mnt/data/{state, cache} && chown 1000:1000 -R /mnt/data"]
#   volumeMounts:
#   - name: filestash-data
#     mountPath: /mnt/data

module "files" {
  source = "./docker-service"

  type              = "deployment"
  name              = "filestash"
  namespace         = module.rclone_files.namespace
  create_namespace  = false
  ingress_enabled   = true
  fqdn              = "files.${var.domain}"
  auth              = "none"
  magicentry_access = true
  image             = "ghcr.io/dzervas/filestash"
  port              = 8334
  node_selector     = { "kubernetes.io/arch" = "amd64" }
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g" # Also defined with env NC_REQUEST_BODY_SIZE, defaults to 1MB
  }

  pvs = {
    "/app/data" = {
      name         = "filestash-data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "25Gi" # Does quite a bit of caching
      retain       = true
    }
  }

  env = {
    APPLICATION_URL = "files.${var.domain}"
    TZ              = var.timezone
  }
}

resource "random_password" "rclone_files_user" {
  length  = 32
  special = false
}

resource "random_password" "rclone_files_pass" {
  length  = 32
  special = false
}

output "rclone_files_webdav_creds" {
  value = {
    user = random_password.rclone_files_user.result
    pass = random_password.rclone_files_pass.result
  }
  sensitive = true
}

module "rclone_files" {
  source = "./docker-service"

  type                    = "deployment"
  name                    = "rclone-files"
  namespace               = "files"
  create_namespace        = true
  ingress_enabled         = false
  image                   = "rclone/rclone:1"
  port                    = 80
  enable_security_context = false
  secrets = {
    "/secret" = "${kubernetes_secret_v1.rclone_files.metadata.0.name}"
  }
  command = ["sh", "-c"]
  args = [
    <<EOF
    mkdir -p /config/rclone && \
    cp /secret/rclone.conf /config/rclone/rclone.conf && \
    rclone serve webdav remote: \
    --vfs-cache-mode full \
    --addr 0.0.0.0:80 \
    --user "${random_password.rclone_files_user.result}" \
    --pass "${random_password.rclone_files_pass.result}"
    EOF
    # --auth-key "${random_password.rclone_files_access_key.result}${random_password.rclone_files_secret_key.result}"
  ]
}

data "external" "crypt_files_password" {
  program = ["bash", "-c", "echo {\\\"password\\\": \\\"$(rclone obscure ${local.op_secrets.rclone.crypt_files_password})\\\", \\\"password2\\\": \\\"$(rclone obscure ${local.op_secrets.rclone.crypt_files_salt})\\\"}"]
}

resource "kubernetes_secret_v1" "rclone_files" {
  metadata {
    name      = "rclone-files"
    namespace = module.rclone_files.namespace
  }

  data = {
    "rclone.conf" = <<EOF
    ${local.main_remote}
    [remote]
    type = crypt
    remote = remote_raw:rclone/files
    filename_encoding = base32768
    password = ${data.external.crypt_files_password.result.password}
    password2 = ${data.external.crypt_files_password.result.password2}
    EOF
  }
}
