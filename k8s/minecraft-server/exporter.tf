resource "kubernetes_manifest" "minecraft_exporter" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "minecraft-exporter"
      namespace = var.prometheus_namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      jobLabel = "minecraft"
      selector = {
        matchLabels = {
          "app" = "minecraft-minecraft-prometheus"
        }
      }
      namespaceSelector = {
        matchNames = [kubernetes_namespace.minecraft.metadata[0].name]
      }
      endpoints = [{
        port     = "prometheus"
        interval = "15s"
      }]
    }
  }
}
