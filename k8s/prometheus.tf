resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "prometheus"
    labels = {
      # Required for the blackbox exporters
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

resource "kubernetes_network_policy_v1" "prometheus_grafana" {
  metadata {
    name      = "allow-prometheus-grafana"
    namespace = helm_release.prometheus.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "prometheus"
        "operator.prometheus.io/name" = "prometheus-kube-prometheus-prometheus"
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
