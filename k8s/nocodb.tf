locals {
  nocodb_age_key_id = local.op_secrets["Related Items"]["NocoDB Age key"]
}

data "onepassword_item" "nocodb_age_key" {
  vault = var.op_vault
  uuid  = local.nocodb_age_key_id
}

module "nocodb" {
  source = "./docker-service"

  type             = "statefulset"
  name             = "nocodb"
  fqdn             = "db.${var.domain}"
  create_namespace = true
  ingress_enabled  = true
  auth             = "mtls"
  #   vpn_bypass_auth  = true
  #   vpn_cidrs        = var.vpn_cidrs
  node_selector = { "kubernetes.io/arch" = "arm64" }
  image         = "nocodb/nocodb:latest"
  port          = 8080
  retain_pvs    = true
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "1m" # Also defined with env NC_REQUEST_BODY_SIZE, defaults to 1MB
  }
  pvs = {
    "/usr/app/data/" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }
  env = {
    TZ                     = var.timezone
    NC_PUBLIC_URL          = "https://db.${var.domain}"
    NC_S3_ENDPOINT         = "rclone.rclone.svc.cluster.local:8080"
    NC_S3_BUCKET_NAME      = "nocodb"
    NC_S3_REGION           = "auto"
    NC_S3_FORCE_PATH_STYLE = true
    NC_S3_ACCESS_KEY       = random_password.rclone_access_key.result
    NC_S3_ACCESS_SECRET    = random_password.rclone_secret_key.result
    # TODO: Backup to S3
    # LITESTREAM_S3_ENDPOINT      = "rclone.rclone.svc.cluster.local:8080"
    # LITESTREAM_S3_BUCKET_NAME   = "nocodb"
    # LITESTREAM_S3_REGION        = "auto"
    # LITESTREAM_S3_PATH          = "backups"
    # LITESTREAM_S3_ACCESS_KEY    = random_password.rclone_access_key.result
    # LITESTREAM_S3_ACCESS_SECRET = random_password.rclone_secret_key.result
    # LITESTREAM_RETENTION        = "720" # 30 days
    # LITESTREAM_AGE_PUBLIC_KEY   = data.onepassword_item.nocodb_age_key.public_key
    # LITESTREAM_AGE_SECRET_KEY   = data.onepassword_item.nocodb_age_key.private_key
  }
}
