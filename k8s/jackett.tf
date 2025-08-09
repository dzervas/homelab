module "jackett" {
  source = "./docker-service"

  type  = "statefulset"
  name  = "jackett"
  fqdn  = "search.${var.domain}"
  auth  = "mtls"
  image = "ghcr.io/elfhosted/jackett:rolling"
  port  = 9117

  image_pull_policy = true

  liveness_http_path = "/health"

  pvs = {
    "/config" = {
      name = "config"
      size = "512Mi"
    }
  }

  env = {
    TZ   = var.timezone
  }
}

module "flaresolverr" {
  source = "./docker-service"

  namespace = module.jackett.namespace
  create_namespace = false

  type  = "deployment"
  name  = "flaresolverr"
  image = "ghcr.io/flaresolverr/flaresolverr"
  port  = 8191

  ingress_enabled = false
  metrics_port = 9191

  env = {
    TZ   = var.timezone

    PROMETHEUS_ENABLED = "true"
    PROMETHEUS_PORT    = "9191"
  }
}
