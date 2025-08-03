module "romm" {
  source = "./docker-service"

  type      = "deployment"
  name      = "romm"
  namespace = "romm"
  fqdn      = "retro.${var.domain}"
  auth      = "mtls"

  # magicentry_access = true

  image = "rommapp/romm"
  port  = 8080

  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g" # Also defined with env NC_REQUEST_BODY_SIZE, defaults to 1MB
    # "nginx.ingress.kubernetes.io/auth-url"        = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    # "nginx.ingress.kubernetes.io/auth-signin"     = "https://auth.dzerv.art/login"
  }

  pvs = {
    "/romm/library" = {
      name = "roms"
      size = "30Gi"
    }
    "/romm/assets" = {
      name = "saves"
      size = "5Gi"
    }
    "/romm/resources" = {
      name = "metadata"
      size = "10Gi"
    }
    "/redis-data" = {
      name = "cache"
      size = "5Gi"
    }
  }

  config_maps = {
    "/romm/config" = "romm-config:rw"
  }

  liveness_http_path = "/api/heartbeat"

  env = {
    TZ = var.timezone

    DB_HOST   = "mariadb-headless"
    DB_NAME   = "romm"
    DB_USER   = "romm"
    ROMM_PORT = 8080
  }

  env_secrets = {
    DB_PASSWD                 = { key = "mariadb-password", secret = "romm-op" }
    ROMM_AUTH_SECRET_KEY      = { key = "auth-secret-key", secret = "romm-op" }
    SCREENSCRAPER_USER        = { key = "screenscraper-user", secret = "romm-op" }
    SCREENSCRAPER_PASSWORD    = { key = "screenscraper-password", secret = "romm-op" }
    RETROACHIEVEMENTS_API_KEY = { key = "retroachievements-api-key", secret = "romm-op" }
    STEAMGRIDDB_API_KEY       = { key = "steamgriddb-api-key", secret = "romm-op" }
  }
}

resource "kubernetes_config_map_v1" "romm_config" {
  metadata {
    name = "romm-config"
    namespace = "romm"
  }

  data = {
    "config.yml" = yamlencode({})
  }
}

resource "helm_release" "romm_mariadb" {
  name      = "mariadb"
  namespace = "romm"
  atomic    = true

  chart = "oci://registry-1.docker.io/bitnamicharts/mariadb"
  # To update: https://github.com/bitnami/charts/blob/main/bitnami/mariadb/Chart.yaml
  version = "21.0.3"

  values = [yamlencode({
    auth = {
      database       = "romm"
      username       = "romm"
      existingSecret = "romm-op"
    }

    primary = {
      persistence = {
        size = "1Gi"
      }
    }
  })]
}

resource "kubernetes_manifest" "romm_op" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "romm-op"
      namespace = "romm"
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [{ extract = { key = "romm" } }]
    }
  }
}
