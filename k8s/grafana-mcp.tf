module "grafana_mcp_ingress" {
  source = "./ingress-block"

  namespace = kubernetes_namespace.grafana.metadata[0].name
  fqdn      = "mcp.${local.grafana_fqdn}"
}

resource "helm_release" "grafana_mcp" {
  name       = "grafana-mcp"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana-mcp"
  version    = "0.1.1"
  atomic     = true

  values = [yamlencode({
    grafana = {
      url = "http://grafana"
      apiKeySecret = {
        name = "grafana-mcp-op"
        key  = "sa-token"
      }
    }

    # ingress = module.grafana_ingress.host_list
  })]
}

resource "kubernetes_manifest" "grafana_mcp_op" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "grafana-mcp-op"
      namespace = kubernetes_namespace.grafana.metadata[0].name
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [{ extract = { key = "grafana-mcp" } }]
    }
  }
}

resource "kubernetes_network_policy_v1" "grafana_mcp_n8n_access" {
  metadata {
    name      = "grafana-mcp-n8n-access"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "mcp-server"
        "app.kubernetes.io/instance"  = "grafana-mcp"
        "app.kubernetes.io/name"      = "grafana-mcp"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "n8n"
          }
        }
      }
    }
  }
}
