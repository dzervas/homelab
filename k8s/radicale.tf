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
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "radicale-secrets-op"
      namespace = module.radicale.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/radicale"
    }
  }
}

resource "kubernetes_manifest" "radicale_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta1"
    kind       = "RecurringJob"
    metadata = {
      name      = "radicale-backups"
      namespace = kubernetes_namespace.longhorn-system.metadata.0.name
    }
    spec = {
      cron        = "0 0 * * *"
      task        = "backup"
      retain      = 30
      concurrency = 1
    }
  }
}

resource "kubernetes_labels" "radicale_backup" {
  api_version = "v1"
  kind        = "PersistentVolumeClaim"
  metadata {
    name      = "originals-radicale-0"
    namespace = module.radicale.namespace
  }
  labels = {
    "recurring-job.longhorn.io/source"      = "enabled"
    "recurring-job.longhorn.io/radicale-backups" = "enabled"
  }
}
