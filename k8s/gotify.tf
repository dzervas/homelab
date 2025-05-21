module "gotify" {
  source = "./docker-service"

  type              = "statefulset"
  name              = "gotify"
  image             = "gotify/server"
  image_pull_policy = true
  port              = 80

  fqdn              = "notify.${var.domain}"
  auth              = "mtls"
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "32m" # Also defined in the settings
  }

  retain_pvs = true
  pvs = {
    "/app/data" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi" # It's actually 10, but I can't edit the statefulset
      retain       = true
    }
  }

  env = {
    TZ = var.timezone
    # GOTIFY_SERVER_TRUSTEDPROXIES = "10.42.0.0/16"
    GOTIFY_DEFAULTUSER_NAME = "dzervas"
    // Set the default pass from 1password
  }
}

resource "kubernetes_manifest" "gotify_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta1"
    kind       = "RecurringJob"
    metadata = {
      name      = "gotify-backups"
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

resource "kubernetes_labels" "gotify_backup" {
  api_version = "v1"
  kind        = "PersistentVolumeClaim"
  metadata {
    name      = "data-gotify-0"
    namespace = module.gotify.namespace
  }
  labels = {
    "recurring-job.longhorn.io/source"         = "enabled"
    "recurring-job.longhorn.io/gotify-backups" = "enabled"
  }
}

resource "kubernetes_network_policy_v1" "gotify_n8n" {
  metadata {
    name      = "allow-gotify-n8n"
    namespace = module.gotify.namespace
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "n8n"
          }
        }
        pod_selector {
          match_labels = {
            "service" = "n8n"
          }
        }
      }
    }
  }
}
