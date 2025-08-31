resource "helm_release" "cloudnative_pg" {
  name             = "cloudnative-pg"
  create_namespace = true
  repository       = "oci://ghcr.io/cloudnative-pg/charts"
  chart            = "cloudnative-pg"

  # To update: https://cloudnative-pg.io/documentation/1.27/installation_upgrade
  version = "0.26.0"
  # atomic  = true

  values = [yamlencode({
    fullnameOverride = "cnpg"

    monitoring = {
      podMonitorEnabled = true
      grafanaDashboard  = { create = true }
    }
  })]
}

resource "kubernetes_manifest" "cnpg_cluster" {
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind = "Cluster"
    metadata = {
      name = "cloudnative-pg"
      namespace = helm_release.cloudnative_pg.namespace
    }
    spec = {
      instances = 3
      storage = {
        size = "5Gi"
        storageClass = "standard"
      }

      monitoring = {
        enablePodMonitor = true
      }
    }
  }
}
