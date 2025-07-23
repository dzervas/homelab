resource "helm_release" "mimir" {
  name       = "mimir"
  namespace  = kubernetes_namespace_v1.prometheus.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = "5.7.0"
  atomic     = true

  values = [
    yamlencode({
      # Disable sub charts
      alertmanager       = { enabled = false }
      gateway            = { enabled = false }
      minio              = { enabled = false }
      nginx              = { enabled = false }
      overrides_exporter = { enabled = false }
      query_scheduler    = { enabled = false }
      rollout_operator   = { enabled = false }
      ruler              = { enabled = false }
    }),
    yamlencode({
      # Mimir config
      mimir = {
        structuredConfig = {
          multitenancy_enabled = false # Otherwise it requires an Org ID
          blocks_storage = { backend = "filesystem" }
          common = {
            storage = { backend = "filesystem" }
          }
        }
      }
    }),
    yamlencode({
      # Component config
      compactor = {
        persistentVolume = { size = "10Gi" }
      }
      ingester = {
        zoneAwareReplication = { enabled = false }
      }
      store_gateway = {
        zoneAwareReplication = { enabled = false }
        persistentVolume = { size = "5Gi" }
      }
    }),
    yamlencode({
      # Self monitoring
      metaMonitoring = {
        dashboards     = { enabled = true }
        serviceMonitor = { enabled = true }
        prometheusRule = {
          enabled     = true
          mimirAlerts = true
          mimirRules  = true
        }
      }
    })
  ]
}

resource "kubernetes_network_policy_v1" "mimir_grafana" {
  metadata {
    name      = "allow-mimir-grafana"
    namespace = helm_release.prometheus.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "query-frontend"
        "app.kubernetes.io/instance"  = "mimir"
        "app.kubernetes.io/name"      = "mimir"
      }
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "grafana"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "grafana"
          }
        }
      }
    }
  }
}
