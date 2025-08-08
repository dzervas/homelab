module "headscale" {
  source = "./docker-service"

  type  = "deployment"
  name  = "headscale"
  fqdn  = "vpn.${var.domain}"
  auth  = "none"
  image = "ghcr.io/juanfont/headscale"
  port  = 8080
  args  = ["serve"]
  # TODO: Don't terminate the SSL at the ingress

  metrics_port = 9090

  # liveness_http_path = "/"

  pvs = {
    "/var/lib/headscale" = {
      name = "db"
      size = "512Mi"
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
      server_url            = "https://vpn.${var.domain}"
      listen_addr           = "0.0.0.0:8080"
      metrics_listen_addr   = "0.0.0.0:9090"

      # grpc_listen_addr    = "0.0.0.0:50443"
      # grpc_allow_insecure = true

      noise = {
        private_key_path = "/var/lib/headscale/noise_private.key"
      }

      database = {
        type = "sqlite3"
        sqlite = {
          path               = "/var/lib/headscale/db.sqlite"
          write_ahead_log    = true
          wal_autocheckpoint = 1000
        }
      }

      dns = {
        base_domain        = "ts.${var.domain}"
        override_local_dns = false
        extra_records_path = "/etc/headscale/dns.json"
      }

      prefixes = {
        allocation = "sequential"
        v4         = "100.100.50.0/24"
      }

      derp = {
        server = {
          enabled        = false
          region_id      = 999
          region_code    = "homelab"
          region_name    = "HomeLab"
          verify_clients = true
        }

        urls                = ["https://controlplane.tailscale.com/derpmap/default"]
        auto_update_enabled = true
        update_frequency    = "24h"
      }

      ephemeral_node_inactivity_timeout = "30m"

      unix_socket            = "/tmp/headscale.sock"
      unix_socket_permission = "0700"
    })
    "dns.json" = jsonencode([])
  }
}
