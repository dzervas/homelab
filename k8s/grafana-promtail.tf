resource "helm_release" "promtail" {
  name       = "promtail"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.17.0"
  atomic     = true

  values = [yamlencode({
    serviceMonitor = { enabled = true }
  })]
}
