module "headscale" {
  source = "./docker-service"

  type  = "deployment"
  name  = "headscale"
  fqdn  = "vpn.${var.domain}"
  auth  = "none"
  image = "ghcr.io/juanfont/headscale"
  port  = 8080

  metrics_port = 9090

  liveness_http_path  = "/"

  pvs = {
    "/var/lib/headscale" = {
      name = "db"
      size = "1Gi"
    }
  }

  config_maps = {
    "/etc/headscale" = "headscale-config:rw"
  }
}

resource "kubernetes_config_map_v1" "headscale_config" {
  metadata {
    name      = "headscale-config"
    namespace = "headscale"
  }

  data = {
    "config.yaml" = yamlencode({
      disable_check_updates = true
      server_url = "https://vpn.${var.domain}"
      listen_addr = "0.0.0.0:8080"
      metrics_listen_addr = "0.0.0.0:8080"

      dns = {
        base_domain = "ts.${var.domain}"
        # extra_records_path = "/etc/headscale/dns.json"
      }

      prefixes = {
        v4 = "100.100.50.0/24"
      }
    })
  }
}
