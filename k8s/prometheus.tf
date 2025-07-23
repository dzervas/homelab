resource "kubernetes_namespace_v1" "prometheus" {
  metadata {
    name = "prometheus"
    labels = {
      # Required for the blackbox exporters
      "pod-security.kubernetes.io/enforce" = "privileged"
      managed_by                           = "terraform"
    }
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  namespace  = kubernetes_namespace_v1.prometheus.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "75.11.0"
  atomic     = true

  values = [
    yamlencode({
      # Grafana deployed separately
      grafana = { enabled = false }
    }),
    yamlencode({
      # Upgrade CRDs automatically
      crds = {
        upgradeJob = {
          enabled        = true
          forceConflicts = true
        }
      }
    }),
    yamlencode({
      # Default alert rules
      defaultRules = { rules = {
        # RKE2 doesn't have a scheduler pod
        kubeScheduler = false
      } }
    }),
    yamlencode({
      prometheusOperator = { networkPolicy = { enabled = true } }

      prometheus = {
        # Allow it to roam free
        # TODO: Configure this?
        networkPolicy = { enabled = false }

        # Allow rules from any namespace without any special annotation/label
        prometheusSpec = {
          scrapeInterval = "15s"

          podMonitorSelector                  = {}
          podMonitorNamespaceSelector         = { any = true }
          podMonitorSelectorNilUsesHelmValues = false

          ruleSelector                  = {}
          ruleNamespaceSelector         = { any = true }
          ruleSelectorNilUsesHelmValues = false

          serviceMonitorSelector                  = {}
          serviceMonitorNamespaceSelector         = { any = true }
          serviceMonitorSelectorNilUsesHelmValues = false

          # Send everything to mimir
          remoteWrite = [{ url = "http://mimir-distributor-headless:8080/api/v1/push" }]
        }
      }
    })
  ]
}

resource "kubernetes_network_policy_v1" "prometheus_grafana" {
  metadata {
    name      = "allow-prometheus-grafana"
    namespace = helm_release.prometheus.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"      = "prometheus"
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
