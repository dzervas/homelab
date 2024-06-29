resource "kubernetes_ingress_v1" "docker" {
  count = var.ingress_enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = kubernetes_namespace.docker.metadata.0.name
    annotations = merge({
      "cert-manager.io/cluster-issuer"           = "letsencrypt"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      }, var.mtls_enabled ? {
      "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
      "nginx.ingress.kubernetes.io/auth-tls-secret"        = "cert-manager/client-ca-certificate"
      "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"
    } : {})
    labels = {
      managed_by = "terraform"
      service    = var.name
    }
  }

  spec {
    ingress_class_name = "nginx"
    rule {
      host = var.fqdn
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.docker.metadata.0.name
              port {
                number = var.port
              }
            }
          }
        }
      }
    }
    tls {
      hosts       = [var.fqdn]
      secret_name = "${replace(var.fqdn, ".", "-")}-cert"
    }
  }
}
