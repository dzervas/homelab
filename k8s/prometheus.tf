resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "prometheus"
    labels = {
      # Required for the blackbox expoerts
      "pod-security.kubernetes.io/enforce"         = "privileged"
      managed_by                                   = "terraform"
    }
  }
}

resource "helm_release" "prometheus" {
  name             = "prometheus"
  namespace        = kubernetes_namespace_v1.prometheus.metadata[0].name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.3.2"
  atomic           = true

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
