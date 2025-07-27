module "copyparty" {
  source = "./docker-service"

  type      = "deployment"
  name      = "copyparty"
  namespace = "copyparty"
  fqdn      = "files.${var.domain}"
  auth      = "mtls"

  # magicentry_access = true

  image = "ghcr.io/9001/copyparty-ac"
  port  = 3923

  args = [
    "--stats", # metrics
    "--dedup",
    "-v", ".::rw", # Add the default volume
  ]

  liveness_http_path  = "/?reset=/._"
  readiness_http_path = "/?reset=/._"

  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g" # Also defined with env NC_REQUEST_BODY_SIZE, defaults to 1MB
    # "nginx.ingress.kubernetes.io/auth-url"        = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    # "nginx.ingress.kubernetes.io/auth-signin"     = "https://auth.dzerv.art/login"
  }

  pvs = {
    "/w" = {
      name   = "data"
      size   = "100Gi"
    }
  }

  env = {
    TZ = var.timezone

    # enabling mimalloc by replacing "NOPE" with "2" will make some stuff twice as fast, but everything will use twice as much ram:
    # https://github.com/9001/copyparty/blob/hovudstraum/docs/examples/docker/basic-docker-compose/docker-compose.yml#L14C5-L16
    LD_PRELOAD = "/usr/lib/libmimalloc-secure.so.NOPE"
  }
}
