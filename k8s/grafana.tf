locals {
  grafana_fqdn = "grafana.${var.domain}"
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = "grafana"
    labels = {
      managed_by = "terraform"
    }
  }
}

module "grafana_ingress" {
  source = "./ingress-block"

  namespace = kubernetes_namespace.grafana.metadata[0].name
  fqdn      = local.grafana_fqdn
  additional_annotations = {
    # "nginx.ingress.kubernetes.io/auth-snippet"                          = "proxy_set_header X-WEBAUTH-USER admin;"
    "nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream" = "true"
  }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "9.2.10"
  atomic     = true

  values = [yamlencode({
    rbac = {
      namespaced = true
    }
    persistence = {
      enabled          = true
      storageClassName = "openebs-replicated"
    }
    ingress = module.grafana_ingress.host_list
    "grafana.ini" = {
      users = {
        allow_sign_up = false
      }
    }
    datasources = {
      "datasources.yaml" = {
        apiVersion = 1
        datasources = [
          {
            name = "Loki"
            type = "loki"
            url  = "http://loki-gateway"
          },
          {
            name = "Prometheus"
            type = "prometheus"
            url  = "http://prometheus-kube-prometheus-prometheus.prometheus.svc.cluster.local:9090"
          },
        ]
      }
    }
    nodeSelector = {
      provider = "oracle"
    }
  })]
}
