resource "helm_release" "victoriametrics" {
  name             = "victoriametrics"
  namespace        = "victoriametrics"
  create_namespace = true
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-k8s-stack"
  # To update: https://github.com/VictoriaMetrics/helm-charts/releases?q=victoria-metrics-k8s-stack&expanded=true
  # https://docs.victoriametrics.com/helm/victoriametrics-k8s-stack/#upgrade-guide
  version = "0.58.2"
  atomic  = true

  values = [yamlencode({
    # Produce sensible names
    fullnameOverride = "victoriametrics"

    vmsingle = {
      spec = {
        retentionPeriod = "1y"
        nodeSelector = {
          provider = "oracle"
        }
      }
    }

    external = {
      grafana = {
        host       = "grafana.dzerv.art"
        datasource = "Victoria"
      }
    }

    defaultDashboards = {
      enabled = true
      labels = {
        grafana_dashboard = "1"
      }
    }

    # kubeProxy = {
    #   enabled = true
    #   service = {
    #     selector = {
    #       component = "kube-proxy"
    #     }
    #   }
    # }
    # https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/values.yaml#L111

    # TODO: The following listen at pod-localhost by default so we can't scrape them
    # TODO: Scrape RKE2 metrics too: https://docs.rke2.io/reference/metrics
    kubeEtcd              = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeControllerManager = { enabled = false }
    defaultRules = {
      groups = {
        etcd                              = { enabled = false }
        kubernetesSystemScheduler         = { enabled = false }
        kubernetesSystemControllerManager = { enabled = false }
      }
    }

    # NixOS defined
    prometheus-node-exporter = { enabled = false }
    # Defined in the grafana tf module
    grafana = {
      enabled               = false
      forceDeployDatasource = true
    }
  })]
}

resource "kubernetes_manifest" "node_exporter_scraper" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMNodeScrape"

    metadata = {
      name      = "nixos-node-exporter"
      namespace = helm_release.victoriametrics.namespace
    }

    spec = {
      scheme = "http"
      port   = "9100"
      path   = "/metrics"

      interval = "30s"

      # Got from the default node-exporter: https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-k8s-stack/values.yaml#L972-L987
      jobLabel = "jobLabel"
      metricRelabelConfigs = [{
        action        = "drop"
        source_labels = ["mountpoint"]
        regex         = "/var/lib/kubelet/pods.+"
      }]
    }
  }
}

resource "kubernetes_manifest" "smartctl_exporter_scraper" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMNodeScrape"

    metadata = {
      name      = "nixos-smartctl-exporter"
      namespace = helm_release.victoriametrics.namespace
    }

    spec = {
      scheme = "http"
      port   = "9633"
      path   = "/metrics"

      interval = "1m"

      jobLabel = "jobLabel"
    }
  }
}

# Add the prometheys CRDs so that vm can scrape servicemonitors, etc.
resource "helm_release" "prometheus_crds" {
  name       = "prometheus-crds"
  namespace  = helm_release.victoriametrics.namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  version    = "22.0.1"
  atomic     = true
}

# Allow for everything (VPN CIDR didn't work!) to reach the operator webhook
resource "kubernetes_network_policy_v1" "victoriametrics_grafana" {
  metadata {
    name      = "allow-victoriametrics-grafana"
    namespace = helm_release.victoriametrics.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "managed-by"                  = "vm-operator"
        "app.kubernetes.io/name"      = "vmsingle"
        "app.kubernetes.io/instance"  = "victoriametrics"
        "app.kubernetes.io/component" = "monitoring"
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

resource "kubernetes_network_policy_v1" "victoriametrics_op_webhook" {
  metadata {
    name      = "victoriametrics-op-webhook"
    namespace = helm_release.victoriametrics.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = "victoria-metrics-operator"
        "app.kubernetes.io/instance" = "victoriametrics"
      }
    }

    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {}
        pod_selector {}
      }
      from {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 9443
      }
    }
  }
}
