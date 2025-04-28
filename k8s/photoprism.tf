module "photoprism" {
  source = "./docker-service"

  type  = "deployment"
  name  = "photoprism"
  auth  = "mtls"
  fqdn  = "photos.${var.domain}"
  image = "photoprism/photoprism:latest"
  port  = 2342
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g"
  }

  retain_pvs = true
  pvs = {
    "/photoprism/originals" = {
      name         = "originals"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "100Gi"
      retain       = true
    }
    "/photoprism/storage" = {
      name         = "config"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }

  # /run belongs to uid 0 instead of 1000
  enable_security_context = false
  env = {
    PHOTOPRISM_DEFAULT_TIMEZONE = var.timezone
    TZ                          = var.timezone
    PHOTOPRISM_APP_NAME         = "DZervArt Photos"
    PHOTOPRISM_SITE_URL         = "https://photos.${var.domain}"
    PHOTOPRISM_SITE_TITLE       = "DZervArt Photos"
    PHOTOPRISM_TRUSTED_PROXY    = "10.43.0.0/16"
    PHOTOPRISM_UID              = 1000
    PHOTOPRISM_GID              = 1000
    # PHOTOPRISM_DISABLE_CHOWN    = true
  }

  env_secrets = {
    PHOTOPRISM_ADMIN_USERNAME = {
      secret = "photoprism-secrets-op"
      key    = "username"
    }
    PHOTOPRISM_ADMIN_PASSWORD = {
      secret = "photoprism-secrets-op"
      key    = "password"
    }
  }
}

resource "kubernetes_manifest" "photoprism_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "photoprism-secrets-op"
      namespace = module.photoprism.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/photoprism"
    }
  }
}
