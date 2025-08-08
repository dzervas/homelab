module "headplane" {
  source = "./docker-service"

  type  = "deployment"
  name  = "headplane"
  fqdn  = "mgmt.${var.domain}"
  auth  = "mtls"
  image = "ghcr.io/tale/headplane"
  port  = 3000

  namespace        = "headscale"
  create_namespace = false

  liveness_http_path = "/"

  pvs = {
    "/var/lib/headplane" = {
      name = "headplane-data"
      size = "1Gi"
    }
  }

  config_maps = {
    "/etc/headplane" = "headplane-config:rw"
    "/etc/headscale" = "headscale-config:rw"
  }
}

resource "kubernetes_config_map_v1" "headplane_config" {
  metadata {
    name      = "headplane-config"
    namespace = "headscale"
  }

  data = {
    "config.yaml" = yamlencode({
      headplane = {
        url = "https://vpn.${var.domain}"
        dns_records_path = "/etc/headscale/dns.json"
      }
    })
  }
}
