resource "helm_release" "external-secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  # For updates: https://github.com/external-secrets/external-secrets/releases
  version = "0.18.2"
  atomic  = true

  values = [yamlencode({
    serviceMonitor = {
      enabled = true
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

# Must apply above helm release before applying this
resource "kubernetes_manifest" "password_generator" {
  manifest = {
    apiVersion = "generators.external-secrets.io/v1alpha1"
    kind       = "ClusterGenerator"
    metadata = {
      name      = "password"
    }
    spec = {
      kind = "Password"
      generator = {
        passwordSpec ={
          length = 42
          symbolCharacters = "-_+=~<>,."
          allowRepeat = true
        }
      }
    }
  }

  depends_on = [helm_release.external-secrets]
}

# Requires Service Account credentials:
# 1password.com > developer tools > Infrastructure Secrets Management > Other > Create a Service Account
# Save the token to op
# k create secret generic onepasswordsdk-sa-token --namespace external-secrets --from-literal=token=(op item get --vault Private "<name>" --fields credential --reveal)
resource "kubernetes_manifest" "_1password_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name      = "1password"
    }
    spec = {
      provider = {
        onepasswordSDK = {
          vault = "k8s-secrets"
          auth  = {
            serviceAccountSecretRef = {
              namespace = helm_release.external-secrets.namespace
              name = "onepasswordsdk-sa-token"
              key  = "token"
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external-secrets]
}

# Cluster-wide ghcr access
resource "kubernetes_manifest" "ghcr_cluster_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterExternalSecret"
    metadata = {
      name      = "ghcr-cluster-secret"
    }
    spec = {
      externalSecretName = "ghcr-cluster-secret"
      namespaceSelectors = [
        { matchLabels = { ghcrCreds = "enabled" } },
      ]
      externalSecretSpec = {
        refreshInterval = "1h"
        secretStoreRef = {
          name = "1password"
          kind = "ClusterSecretStore"
        }
        target = {
          name           = "ghcr-cluster-secret"
          creationPolicy = "Owner"
          template = {
            type = "kubernetes.io/dockerconfigjson"
            engineVersion = "v2"
            data = {
              ".dockerconfigjson" = jsonencode({
                auths = {
                  "ghcr.io" = {
                    username = "{{ .ghcr_username }}"
                    password = "{{ .ghcr_token }}"
                  }
                }
              })
            }
          }
        }

        dataFrom = [ { extract = { key = "external-secrets" } } ]
      }
    }
  }
}

# TODO: Manage admission controller webhooks for all namespaces (if labeled) as follows
# Allow access to the admissioncontroller webhook from tf/kubectl/etc.
resource "kubernetes_network_policy_v1" "external_secrets_webhook" {
  metadata {
    name      = "allow-external-secrets-webhook"
    namespace = helm_release.external-secrets.namespace
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
