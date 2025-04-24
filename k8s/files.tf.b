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
    # "nginx.ingress.kubernetes.io/auth-url"        = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    # "nginx.ingress.kubernetes.io/auth-signin"     = "https://auth.dzerv.art/login"
  }

  init_containers = [{
    name    = "init-permissions"
    image   = "busybox"
    command = ["sh", "-c"]
    args    = ["mkdir -p /app/data/state /app/data/cache && chown 1000:1000 -R /app/data"]
  }]

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

module "rclone_files" {
  source = "./docker-service"

  type                    = "deployment"
  name                    = "rclone-files"
  namespace               = "files"
  create_namespace        = true
  ingress_enabled         = false
  image                   = "rclone/rclone:1"
  port                    = 80
  secrets = {
    "/secret" = "${kubernetes_secret_v1.rclone_files.metadata.0.name}"
  }
  command = ["sh", "-c"]
  args = [
    <<EOF
    cp /secret/rclone.conf /tmp/rclone.conf && \
    rclone config update remote password=$(rclone obscure $CRYPT_PASSWORD) && \
    rclone config update remote password2=$(rclone obscure $CRYPT_SALT) && \
    rclone serve webdav remote: \
    --vfs-cache-mode full \
    --addr 0.0.0.0:80 \
    --user $RCLONE_USER \
    --pass $RCLONE_PASS
    EOF
  ]

  env_secrets = {
    # WebDAV server credentials
    RCLONE_USER = {
      secret = "files-secrets-op"
      key    = "rclone-user"
    }
    RCLONE_PASS = {
      secret = "files-secrets-op"
      key    = "rclone-pass"
    }

    # Crypt remote
    CRYPT_PASSWORD = {
      secret = "files-secrets-op"
      key    = "rclone-crypt-password"
    }
    CRYPT_SALT = {
      secret = "files-secrets-op"
      key    = "rclone-crypt-salt"
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
  }
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
    EOF
  }
}

resource "kubernetes_manifest" "files_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "files-secrets-op"
      namespace = module.files.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/files"
    }
  }
}

resource "kubernetes_manifest" "files_secrets_rclone" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-secrets-op"
      namespace = module.files.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone"
    }
  }
}
