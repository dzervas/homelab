module "rclone" {
  source = "./docker-service"

  type            = "deployment"
  name            = "rclone"
  fqdn            = "s3.${var.domain}"
  ingress_enabled = false
  auth            = "mtls"
  image           = "rclone/rclone:1"
  port            = 8080
  # TODO: Add auth
  args = ["serve", "s3", "remote:/rclone/s3", "--addr 0.0.0.0:8080"]
}

resource "kubernetes_secret_v1" "rclone" {
  metadata {
    name      = "rclone"
    namespace = module.rclone.namespace
  }

  data = {
    "rclone.conf" = base64encode(provider::toml::encode({
      remote = {
        type                 = "onedrive"
        client_id            = local.op_secrets.rclone.client_id
        client_secret        = local.op_secrets.rclone.client_secret
        drive_type           = "business"
        access_scopes        = ["Files.ReadWrite.AppFolder", "Sites.Read.All", "offline_access"]
        no_versions          = true
        hard_delete          = true
        av_override          = true
        metadata_permissions = "read,write"
        auth_url             = "https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/authorize"
        token_url            = "https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/token"
        token                = local.op_secrets.rclone.token
        drive_id             = local.op_secrets.rclone.drive_id
      }
    }))
  }
}
