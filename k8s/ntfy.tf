module "ntfy" {
  source = "./docker-service"

  type            = "statefulset"
  name            = "ntfy"
  fqdn            = "ntfy.${var.domain}"
  ingress_enabled = true
  auth            = "none"
  image           = "binwiederhier/ntfy:latest"
  args            = ["serve"]
  port            = 80
  retain_pvs      = true
  pvs = {
    "/var/lib/ntfy" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
  }
  config_maps = {
    "/etc/ntfy" = "ntfy"
  }
}

resource "kubernetes_config_map" "ntfy_config" {
  metadata {
    name      = "ntfy"
    namespace = module.ntfy.namespace
    labels = {
      managed_by = "terraform"
    }
  }

  data = {
    "server.yml" = yamlencode({
      base-url            = "https://ntfy.${var.domain}"
      upstream-base-url   = "https://ntfy.sh"
      behind-proxy        = true
      auth-default-access = "deny-all"
      auth-file           = "/var/lib/ntfy/user.db"
      cache-file          = "/var/lib/ntfy/cache.db"
    })
  }
}
