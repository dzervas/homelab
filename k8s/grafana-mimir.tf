resource "helm_release" "mimir" {
  name       = "mimir"
  namespace  = kubernetes_namespace_v1.prometheus.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "75.11.0"
  atomic     = true

  values = [
    yamlencode({
      # Disable sub charts
      alertmanager       = { enabled = false }
      gateway            = { enabled = false }
      minio              = { enabled = false }
      nginx              = { enabled = false }
      overrides_exporter = { enabled = false }
      query_frontend     = { enabled = false }
      query_scheduler    = { enabled = false }
      rollout_operator   = { enabled = false }
      ruler              = { enabled = false }
    }),
    yamlencode({
      # Mimir config
      mimir = {
        structuredConfig = {
          common = {
            storage = {
              backend = "filesystem"
              # filesystem = {
              #   directory = "/mimir"
              # }
            }
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
        persistentVolume = { size = "20Gi" }
      }
      store_gateway = {
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

# resource "kubernetes_network_policy_v1" "mimir_grafana" {
#   metadata {
#     name      = "allow-mimir-grafana"
#     namespace = helm_release.prometheus.namespace
#   }
#   spec {
#     pod_selector {
#       match_labels = {
#         "app.kubernetes.io/name"      = "prometheus"
#         "operator.prometheus.io/name" = "prometheus-kube-prometheus-prometheus"
#       }
#     }
#     policy_types = ["Ingress"]
#
#     ingress {
#       from {
#         namespace_selector {
#           match_labels = {
#             "kubernetes.io/metadata.name" = "grafana"
#           }
#         }
#         pod_selector {
#           match_labels = {
#             "app.kubernetes.io/name" = "grafana"
#           }
#         }
#       }
#     }
#   }
# }
