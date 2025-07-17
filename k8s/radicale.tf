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
      name = "originals"
      size = "10Gi"
    }
  }

  run_as_user = 2999
  env = {
    TZ = var.timezone
  }
}
