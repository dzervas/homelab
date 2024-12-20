resource "random_password" "rclone_access_key" {
  length           = 32
  special          = false
  override_special = "_%@"
}

resource "random_password" "rclone_secret_key" {
  length = 32
}

module "rclone" {
  source = "./docker-service"

  type            = "deployment"
  name            = "rclone"
  ingress_enabled = false
  # fqdn            = "s3.${var.domain}"
  # auth            = "mtls"
  image = "rclone/rclone:1"
  port  = 80
  secrets = {
    "/secret" = "${kubernetes_secret_v1.rclone.metadata.0.name}:rw"
  }
  command = ["sh", "-c"]
  args = [
    <<EOF
    mkdir -p /config/rclone && \
    cp /secret/rclone.conf /config/rclone/rclone.conf && \
    rclone serve s3 remote:/rclone/s3 \
    --vfs-cache-mode full \
    --addr 0.0.0.0:80 \
    --auth-key "${random_password.rclone_access_key.result}${random_password.rclone_secret_key.result}"
    EOF
  ]
}

resource "kubernetes_secret_v1" "rclone" {
  metadata {
    name      = "rclone"
    namespace = module.rclone.namespace
  }

  data = {
    "rclone.conf" = <<EOF
    [remote]
    type                 = onedrive
    client_id            = ${local.op_secrets.rclone.client_id}
    client_secret        = ${local.op_secrets.rclone.client_secret}
    drive_type           = business
    access_scopes        = Files.ReadWrite.AppFolder User.Read offline_access
    no_versions          = true
    hard_delete          = true
    av_override          = true
    metadata_permissions = read,write
    auth_url             = https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/authorize
    token_url            = https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/token
    token                = ${local.op_secrets.rclone.token}
    drive_id             = ${local.op_secrets.rclone.drive_id}
    EOF
  }
}
