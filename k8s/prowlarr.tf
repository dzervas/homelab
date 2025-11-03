module "prowlarr" {
  source = "./docker-service"

  type  = "statefulset"
  name  = "prowlarr"
  fqdn  = "search.${var.domain}"
  auth  = "mtls"
  image = "ghcr.io/elfhosted/prowlarr-nightly:rolling"
  port  = 9696

  image_pull_policy = true

  liveness_http_path = "/"

  pvs = {
    "/config" = {
      name = "config"
      size = "512Mi"
    }
  }

  node_selector = {
    "kubernetes.io/arch" = "amd64"
  }

  env = {
    TZ   = var.timezone
  }
}

module "flaresolverr" {
  source = "./docker-service"

  namespace = module.prowlarr.namespace
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

resource "kubernetes_network_policy_v1" "audiobookshelf_access" {
  metadata {
    name      = "audiobookshelf-access"
    namespace = module.prowlarr.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "audiobookshelf"
          }
        }
      }
    }
  }
}
