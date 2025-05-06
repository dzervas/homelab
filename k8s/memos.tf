module "memos" {
  source = "./docker-service"

  type              = "statefulset"
  name              = "memos"
  image             = "ghcr.io/usememos/memos:stable"
  image_pull_policy = true
  port              = 5230

  fqdn              = "notes.${var.domain}"
  auth              = "mtls"
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "32m" # Also defined in the settings
  }

  retain_pvs = true
  pvs = {
    "/var/opt/memos" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi" # It's actually 10, but I can't edit the statefulset
      retain       = true
    }
  }

  env = {
    TZ = var.timezone
  }
}

resource "kubernetes_manifest" "memos_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta1"
    kind       = "RecurringJob"
    metadata = {
      name      = "memos-backups"
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

resource "kubernetes_labels" "memos_backup" {
  api_version = "v1"
  kind        = "PersistentVolumeClaim"
  metadata {
    name      = "data-memos-0"
    namespace = module.memos.namespace
  }
  labels = {
    "recurring-job.longhorn.io/source"        = "enabled"
    "recurring-job.longhorn.io/memos-backups" = "enabled"
  }
}
