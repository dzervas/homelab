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

resource "kubernetes_manifest" "radicale_secrets" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "radicale-secrets-op"
      namespace = module.radicale.namespace
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [ { extract = { key = "radicale" } } ]
    }
  }
}
