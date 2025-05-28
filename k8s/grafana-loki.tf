resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.grafana.metadata.0.name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.6.4"
  atomic     = true

  values = [yamlencode({
    loki = {
      auth_enabled = false
      commonConfig = {
        replication_factor = 1
      }
      storage = {
        type = "filesystem"
      }
      schemaConfig = {
        configs = [
          {
            from         = "2024-06-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index = {
              prefix = "loki_index_"
              period = "24h"
            }
          }
        ]
      }

      limits_config = {
        retention_period = "90d"
      }
      compactor = {
        retention_enabled = true
        retention_delete_delay = "2h"
        delete_request_store = "filesystem"
      }
    }
    deploymentMode = "SingleBinary"
    singleBinary = {
      replicas = 1
      persistence = {
        enabled          = true
        size             = "20Gi"
        storageClassName = "longhorn"
      }
    }
    monitoring = {
      selfMonitoring = {
        grafanaAgent = {
          installOperator = false
        }
      }
    }
    backend = { replicas = 0 }
    read    = { replicas = 0 }
    write   = { replicas = 0 }

    # TODO: Re-enable it
    # lokiCanary = {
    #   enabled = false
    # }
  })]
}
