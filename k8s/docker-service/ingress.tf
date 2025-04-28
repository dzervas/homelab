locals {
  mtls_annotations = {
    "nginx.ingress.kubernetes.io/auth-tls-secret"        = "${local.namespace}/client-ca"
    "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"
    "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
  }
  oauth_annotations = {
    "magicentry.rs/name"                      = var.name
    "magicentry.rs/realms"                    = var.name
    "magicentry.rs/auth-url"                  = "true"
    "magicentry.rs/manage-ingress-nginx"      = "true"
    "nginx.ingress.kubernetes.io/auth-url"    = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    "nginx.ingress.kubernetes.io/auth-signin" = "https://auth.dzerv.art/login"
  }
}

resource "kubernetes_ingress_v1" "docker" {
  count = var.ingress_enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = local.namespace
    labels = {
      managed_by = "terraform"
      service    = var.name
    }

    annotations = merge(
      # Default config
      {
        "cert-manager.io/cluster-issuer"           = "letsencrypt"
        "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      },
      var.ingress_annotations,
      var.auth == "mtls" ? local.mtls_annotations :
      var.auth == "oauth" ? local.oauth_annotations : {}
    )
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
