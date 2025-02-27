resource "helm_release" "external-secrets" {
  name             = "external-secrets"
  namespace        = kubernetes_namespace_v1._1password.metadata.0.name
  create_namespace = false
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  # For updates: https://github.com/external-secrets/external-secrets/releases
  version = "0.14.3"
  values = [yamlencode({
    serviceMonitor = {
      enabled = true
    }
    # webhook = {
    #   certManager = {
    #     enabled = true # Enable cert-manager integration
    #   }
    # }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

# Must apply above helm release before applying this
resource "kubernetes_manifest" "_1password_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "1password"
    }
    spec = {
      provider = {
        onepassword = {
          connectHost = "http://onepassword-connect:8080"
          vaults = {
            "k8s-secrets" = 1
          }
          auth = {
            secretRef = {
              connectTokenSecretRef = {
                namespace = kubernetes_namespace_v1._1password.metadata.0.name
                name      = "connect-token"
                key       = "token"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external-secrets]
}

resource "kubernetes_network_policy_v1" "external_secrets_webhook" {
  metadata {
    name      = "allow-external-secrets-webhook"
    namespace = kubernetes_namespace_v1._1password.metadata.0.name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "external-secrets-webhook"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        # namespace_selector {}
        # TODO: Limit this
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 10250 # Webhook port
      }
    }
  }
}
