resource "kubernetes_namespace" "ente" {
  metadata {
    name = "ente"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

module "ente_server" {
  source = "./docker-service"

  type             = "deployment"
  name             = "ente-server"
  namespace        = kubernetes_namespace.ente.metadata.0.name
  create_namespace = false
  fqdn             = "api.photos.${var.domain}"
  auth             = "mtls"
  image            = "ghcr.io/ente-io/server"
  port             = 8080
  rclone_access    = true

  env = {
    ENTE_CREDENTIALS_FILE = "/config/server.yaml"
  }

  env_secrets = {
    ENTE_DB_PASSWORD = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "postgres-password"
    }
    ENTE_S3_RCLONE_KEY = {
      secret = kubernetes_manifest.ente_s3.manifest.metadata.name
      key    = "access-id"
    }
    ENTE_S3_RCLONE_SECRET = {
      secret = kubernetes_manifest.ente_s3.manifest.metadata.name
      key    = "secret-key"
    }
    ENTE_KEY_ENCRYPTION = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "key-encryption"
    }
    ENTE_KEY_HASH = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "key-hash"
    }
    ENTE_JWT_SECRET = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "jwt-secret"
    }

    ENTE_SMTP_USERNAME = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "smtp-username"
    }
    ENTE_SMTP_PASSWORD = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "smtp-password"
    }
    ENTE_SMTP_EMAIL = {
      secret = kubernetes_manifest.ente_secrets.manifest.metadata.name
      key    = "smtp-username"
    }
  }

  config_maps = {
    "/config" = "ente-config:ro"
  }

  depends_on = [module.ente_db]
}

module "ente_web" {
  source = "./docker-service"

  type             = "deployment"
  name             = "ente-web"
  namespace        = kubernetes_namespace.ente.metadata.0.name
  create_namespace = false
  auth             = "mtls"
  fqdn             = "photos.${var.domain}"
  image            = "ghcr.io/ente-io/web"
  port             = 3000
  # run_as_user      = 101
  # During startup it changes the ownership of /out and changes the files
  # https://github.com/ente-io/ente/blob/main/web/Dockerfile#L61-L66
  enable_security_context = false
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g"
  }

  env = {
    ENTE_API_ORIGIN = "https://${module.ente_server.fqdn}"
  }

  depends_on = [module.ente_server]
}

module "ente_db" {
  source = "./postgres"

  namespace            = kubernetes_namespace.ente.metadata.0.name
  password_secret_name = kubernetes_manifest.ente_secrets.manifest.metadata.name
}

resource "kubernetes_manifest" "ente_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "ente-secrets-op"
      namespace = kubernetes_namespace.ente.metadata.0.name
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/ente"
    }
  }
}

resource "kubernetes_manifest" "ente_s3" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-s3-op"
      namespace = kubernetes_namespace.ente.metadata.0.name
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone-s3"
    }
  }
}

resource "kubernetes_config_map_v1" "ente_config" {
  metadata {
    name      = "ente-config"
    namespace = kubernetes_namespace.ente.metadata.0.name
  }

  data = {
    "server.yaml" = jsonencode({
      db = {
        host = "postgres"
        name = "postgres"
        user = "postgres"
      }
      s3 = {
        are_local_buckets   = true
        use_path_style_urls = true
        rclone = {
          endpoint = "http://rclone.rclone.svc.cluster.local"
          bucket   = "photos"
        }
      }
      apps = {
        "public-albums" = "https://${module.ente_web.fqdn}"
      }

      smtp = {
        host          = "smtp-hve.office365.com"
        port          = 587
        "sender-name" = "DZervArt Photos"
      }

      # internal = {
      #   "disable-registration" = true
      # }
    })
  }
}
