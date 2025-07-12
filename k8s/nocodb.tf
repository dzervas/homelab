module "nocodb" {
  source = "./docker-service"

  type                    = "statefulset"
  name                    = "nocodb"
  fqdn                    = "db.${var.domain}"
  create_namespace        = true
  ingress_enabled         = true
  auth                    = "mtls"
  enable_security_context = false
  rclone_access           = true
  #   vpn_bypass_auth  = true
  #   vpn_cidrs        = var.vpn_cidrs
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
    NC_S3_ENDPOINT         = "rclone.rclone.svc.cluster.local"
    NC_S3_BUCKET_NAME      = "nocodb"
    NC_S3_REGION           = "auto"
    NC_S3_FORCE_PATH_STYLE = true
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

  env_secrets = {
    NC_S3_ACCESS_KEY = {
      secret = "rclone-s3-op"
      key    = "access-id"
    }
    NC_S3_ACCESS_SECRET = {
      secret = "rclone-s3-op"
      key    = "secret-key"
    }
  }
}

resource "kubernetes_manifest" "nocodb_s3" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-s3-op"
      namespace = module.nocodb.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone-s3"
    }
  }
}

resource "kubernetes_network_policy_v1" "nocodb_ingress" {
  metadata {
    name      = "nocodb-ingress"
    namespace = module.nocodb.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "n8n"
          }
        }
      }
    }
  }
}
