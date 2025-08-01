resource "helm_release" "victoriametrics" {
  name             = "victoriametrics"
  namespace        = "victoriametrics"
  create_namespace = true
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-single"
  version          = "0.24.1"
  atomic           = true

  values = [yamlencode({
    server = {
      scrape = {
        enabled = true
        # Additional scraping config:
        # https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-single/values.yaml#L753-L766
        # extraScrapeConfigs = []
      }
    }
  })]
}

resource "helm_release" "victoriametrics_op" {
  name       = "victoriametrics-operator"
  namespace  = helm_release.victoriametrics.namespace
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-operator"
  version    = "0.51.4"
  atomic     = true

  set = [{
    name  = "crds.cleanup.enabled"
    value = "true"
  }]

  values = [yamlencode({
    operator = {
      # If the serviceMonitor gets deleted, delete VM object too
      enable_converter_ownership = true
      # It should reduce  vmagent and vmauth config sync-time and make it predictable.
      useCustomConfigReloader = false
    }
  })]
}

resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  namespace  = helm_release.victoriametrics.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = "6.1.0"
  atomic     = true
}

resource "helm_release" "prometheus_crds" {
  name       = "prometheus-crds"
  namespace  = helm_release.victoriametrics.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  version    = "22.0.1"
  atomic     = true
}

resource "kubernetes_network_policy_v1" "victoriametrics_grafana" {
  metadata {
    name      = "allow-victoriametrics-grafana"
    namespace = helm_release.victoriametrics.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app"                        = "server"
        "app.kubernetes.io/name"     = "victoria-metrics-single"
        "app.kubernetes.io/instance" = "victoriametrics"
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
