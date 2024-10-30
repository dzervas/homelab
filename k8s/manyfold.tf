resource "random_string" "manyfold_secret" {
  length = 40
}

module "manyfold" {
  source = "./docker-service"

  type            = "statefulset"
  name            = "three"
  fqdn            = "three.${var.domain}"
  ingress_enabled = true
  auth            = "mtls"
  image           = "ghcr.io/manyfold3d/manyfold-solo:0.86.0"
  port            = 3214
  retain_pvs      = true
  pvs = {
    "/config" = {
      name         = "config"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
    "/libraries" = {
      name         = "libraries"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }

  env = {
    SECRET_KEY_BASE = random_string.manyfold_secret.result
    PUID            = 1000
    PGID            = 1000
  }
  # TODO: Needs service annotation:
  # "nginx.ingress.kubernetes.io/proxy-body-size" = "4096m"
}
