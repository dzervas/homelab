module "nocodb" {
  source = "./docker-service"

  type = "statefulset"
  name = "nocodb"
  fqdn = "db.${var.domain}"
  auth = "mtls"

  image      = "nocodb/nocodb:latest"
  port       = 8080
  retain_pvs = true

  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "1m" # Also defined with env NC_REQUEST_BODY_SIZE, defaults to 1MB
  }

  pvs = {
    "/usr/app/data/" = {
      name = "data"
      size = "10Gi"
    }
  }

  env = {
    TZ            = var.timezone
    NC_PUBLIC_URL = "https://db.${var.domain}"
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
