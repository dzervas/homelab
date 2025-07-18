# Distribute the client ca to all namespaces so that ingress-nginx has access to it
resource "kubernetes_manifest" "kubernetes_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "kubernetes"
    }
    spec = {
      provider = {
        kubernetes = {
          remoteNamespace = helm_release.cert_manager.namespace
          server = {
            caProvider = {
              type = "ConfigMap"
              name = "kube-root-ca.crt"
              key = "ca.crt"
              namespace = helm_release.cert_manager.namespace
            }
          }
          auth = {
            serviceAccount = {
              name = kubernetes_service_account_v1.cm_global_client_ca.metadata[0].name
              namespace = kubernetes_service_account_v1.cm_global_client_ca.metadata[0].namespace
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_role_v1" "cm_global_client_ca" {
  metadata {
    name      = "external-secrets-client-ca"
    namespace = helm_release.cert_manager.namespace
  }

  rule {
    api_groups = [""]
    verbs     = ["list"]
    resources = ["secrets"]
  }
  rule {
    api_groups = [""]
    verbs     = ["get", "watch"]
    resources = ["secrets"]
    resource_names = [ kubernetes_manifest.cm_client_ca.manifest.metadata.name ]
  }
  rule {
    api_groups = [""]
    verbs     = ["get"]
    resources = ["configmap"]
    resource_names = [ "kube-root-ca.crt" ]
  }
}

resource "kubernetes_role_binding_v1" "cm_global_client_ca" {
  metadata {
    name      = "external-secrets-client-ca"
    namespace = helm_release.cert_manager.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.cm_global_client_ca.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.cm_global_client_ca.metadata[0].name
    namespace = kubernetes_service_account_v1.cm_global_client_ca.metadata[0].namespace
  }
}

# Create a service account for external-secrets to access the secret
resource "kubernetes_service_account_v1" "cm_global_client_ca" {
  metadata {
    name      = "external-secrets-client-ca"
    namespace = helm_release.cert_manager.namespace
  }
}

# Create a ClusterExternalSecret to distribute the client ca to all namespaces
resource "kubernetes_manifest" "cm_global_client_ca" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterExternalSecret"
    metadata = {
      name = "cm-global-client-ca"
    }
    spec = {
      externalSecretName = "client-ca"
      namespaceSelectors = [
        { matchLabels: {} }, # Allow all
      ]
      externalSecretSpec = {
        refreshInterval = "1h"
        secretStoreRef = {
          name = "kubernetes"
          kind = "ClusterSecretStore"
        }
        data = [{
          secretKey = "ca.crt"
          remoteRef = {
            key = kubernetes_manifest.cm_client_ca.manifest.spec.secretName
            namespace = kubernetes_manifest.cm_client_ca.manifest.metadata.namespace
            property = "ca.crt"
          }
        }]
      }
    }
  }
}
