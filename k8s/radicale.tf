module "radicale" {
  source = "./docker-service"

  type  = "statefulset"
  name  = "radicale"
  auth  = "mtls"
  fqdn  = "dav.${var.domain}"
  image = "tomsquest/docker-radicale"
  port  = 5232

  retain_pvs = true
  pvs = {
    "/data" = {
      name         = "originals"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }

  run_as_user = 2999
  env = {
    TZ = var.timezone
  }
}
