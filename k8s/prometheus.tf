resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "61.1.1"
  atomic           = true
  create_namespace = true

  values = [yamlencode({
    grafana      = { enabled = false }
    alertmanager = { enabled = false }
    prometheus = {
      prometheusSpec = {
        scrapeInterval                          = "30s"
        evaluationInterval                      = "30s"
        podMonitorSelectorNilUsesHelmValues     = false
        serviceMonitorSelectorNilUsesHelmValues = false
      }
    }
  })]
}
