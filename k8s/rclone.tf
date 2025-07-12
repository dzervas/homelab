locals {
  main_remote = <<EOF
  [remote_raw]
  type                 = onedrive
  drive_type           = business
  access_scopes        = Files.ReadWrite.AppFolder User.Read offline_access
  no_versions          = true
  hard_delete          = true
  av_override          = true
  metadata_permissions = read,write
  EOF
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
    "/secret" = kubernetes_secret_v1.rclone.metadata[0].name
  }
  command = ["sh", "-c"]
  # VFS Cache results in a horrible performance drop for round-trip write-read operations
  args = [
    <<EOF
    cp /secret/rclone.conf /tmp/rclone.conf && \
    rclone config update remote password=$(rclone obscure $CRYPT_PASSWORD) && \
    rclone config update remote password2=$(rclone obscure $CRYPT_SALT) && \
    rclone serve s3 remote: \
    --cache-dir /tmp/.cache \
    --vfs-cache-mode full \
    --addr 0.0.0.0:80 \
    --auth-key "$RCLONE_ACCESS_ID,$RCLONE_SECRET_KEY"
    EOF
  ]

  env_secrets = {
    # S3 server credentials
    RCLONE_ACCESS_ID = {
      secret = "rclone-s3-op"
      key    = "access-id"
    }
    RCLONE_SECRET_KEY = {
      secret = "rclone-s3-op"
      key    = "secret-key"
    }

    # Crypt remote
    CRYPT_PASSWORD = {
      secret = "rclone-secrets-op"
      key    = "crypt-password"
    }
    CRYPT_SALT = {
      secret = "rclone-secrets-op"
      key    = "crypt-salt"
    }

    # OneDrive remote
    RCLONE_ONEDRIVE_TENANT = {
      secret = "rclone-secrets-op"
      key    = "onedrive-tenant"
    }
    RCLONE_ONEDRIVE_CLIENT_ID = {
      secret = "rclone-secrets-op"
      key    = "onedrive-client-id"
    }
    RCLONE_ONEDRIVE_CLIENT_SECRET = {
      secret = "rclone-secrets-op"
      key    = "onedrive-client-secret"
    }
    RCLONE_ONEDRIVE_TOKEN = {
      secret = "rclone-secrets-op"
      key    = "onedrive-token"
    }
    RCLONE_ONEDRIVE_DRIVE_ID = {
      secret = "rclone-secrets-op"
      key    = "onedrive-drive-id"
    }
  }

  env = {
    RCLONE_CONFIG             = "/tmp/rclone.conf"
    RCLONE_ONEDRIVE_AUTH_URL  = "https://login.microsoftonline.com/$(RCLONE_ONEDRIVE_TENANT)/oauth2/v2.0/authorize"
    RCLONE_ONEDRIVE_TOKEN_URL = "https://login.microsoftonline.com/$(RCLONE_ONEDRIVE_TENANT)/oauth2/v2.0/token"
  }
}

resource "kubernetes_secret_v1" "rclone" {
  metadata {
    name      = "rclone"
    namespace = module.rclone.namespace
  }

  data = {
    "rclone.conf" = <<EOF
    ${local.main_remote}
    [remote]
    type = crypt
    remote = remote_raw:rclone/s3
    filename_encoding = base32768
    EOF
  }
}

resource "kubernetes_manifest" "rclone_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-secrets-op"
      namespace = module.rclone.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone"
    }
  }
}

resource "kubernetes_manifest" "rclone_s3_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-s3-op"
      namespace = module.rclone.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone-s3"
    }
  }
}

resource "kubernetes_network_policy_v1" "rclone_ingress" {
  metadata {
    name      = "allow-rclone-ingress"
    namespace = module.rclone.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {}
        pod_selector {
          match_labels = {
            "rclone/enable" = "true"
          }
        }
      }
    }
  }
}
