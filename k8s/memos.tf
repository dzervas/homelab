module "memos" {
  source = "./docker-service"

  type              = "statefulset"
  name              = "memos"
  image             = "ghcr.io/usememos/memos:stable"
  image_pull_policy = true
  port              = 5230

  fqdn = "notes.${var.domain}"
  auth = "mtls"
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "32m" # Also defined in the settings
  }

  retain_pvs = true
  pvs = {
    "/var/opt/memos" = {
      name = "data"
      size = "1Gi" # It's actually 10, but I can't edit the statefulset
    }
  }

  env = {
    TZ         = var.timezone
    MEMOS_PORT = 5230
  }
}

resource "kubernetes_network_policy_v1" "memos_n8n" {
  metadata {
    name      = "allow-memos-n8n"
    namespace = module.memos.namespace
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

resource "kubernetes_manifest" "memos_backup" {
  manifest = {
    apiVersion = "gemini.fairwinds.com/v1"
    kind       = "SnapshotGroup"
    metadata = {
      name      = "data-memos"
      namespace = module.memos.namespace
    }
    spec = {
      persistentVolumeClaim = { claimName = "data-memos-0" }
      schedule = [
        { every = "day", keep = 7 },
        { every = "week", keep = 4 },
        { every = "month", keep = 3 }
      ]
    }
  }
}
