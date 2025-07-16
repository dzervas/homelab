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
    useStatefulSet = true # OpenEBS doesn't support RWX
    persistence = {
      enabled = true
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

    rbac = {
      useExistingClusterRole = kubernetes_cluster_role_v1.grafana.metadata[0].name
    }

    # Allow arbitrary services to create grafana resources through a configmap
    sidecar = {
      enableUniqueFilenames = true # Avoid overwrites due to same filenames

      # Needs label `grafana_alert=1`
      alerts = {
        enabled = true
        resource = "configmap"
        searchNamespace = "ALL"
      }

      # Needs label `grafana_dashboard=1`
      dashboards = {
        enabled = true
        resource = "configmap"
        searchNamespace = "ALL"

        defaultFolderName = "collected" # target subdirectory in the PV

        # grafana_folder annotation can describe the target folder (within grafana)
        folderAnnotation = "grafana_folder"

        # Place all collected dashboards under this folder
        provider = { folder = "Collected" }
      }

      # Needs label `grafana_datasource=1`
      datasources = {
        enabled = true
        resource = "configmap"
        searchNamespace = "ALL"
      }

      # Needs label `grafana_plugin=1`
      # plugins = {
      #   enabled = true
      #   resource = "configmap"
      #   searchNamespace = "ALL"
      # }

      # Needs label `grafana_notifier=1`
      notifiers = {
        enabled = true
        resource = "configmap"
        searchNamespace = "ALL"
      }
    }
  })]
}

# Define our own cluster role since by default it has access to all secrets too
resource "kubernetes_cluster_role_v1" "grafana" {
  metadata {
    name = "grafana"
  }
  rule {
    api_groups = [""]
    resources = ["configmaps"]
    verbs = ["get", "list", "watch"]
  }
}
