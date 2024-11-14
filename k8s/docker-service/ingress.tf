resource "kubernetes_ingress_v1" "docker" {
  count = var.ingress_enabled ? 1 : 0
  metadata {
    name      = var.name
    namespace = local.namespace
    annotations = merge({
      "cert-manager.io/cluster-issuer"           = "letsencrypt"
      "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      },
      var.auth == "mtls" ? {
        "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
        "nginx.ingress.kubernetes.io/auth-tls-secret"        = "cert-manager/client-ca-certificate"
        "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"
      } :
      var.auth == "oauth" ? {
        "magicentry.rs/realms"                       = var.name
        "magicentry.rs/auth-url"                     = "true"
        "magicentry.rs/manage-ingress-nginx"         = "true"
        "nginx.ingress.kubernetes.io/auth-url"       = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
        "nginx.ingress.kubernetes.io/auth-signin"    = "https://auth.dzerv.art/login"
        "nginx.ingress.kubernetes.io/server-snippet" = <<EOF
          location = /__magicentry_auth_code {
            add_header Set-Cookie "code=$arg_code; Path=/; HttpOnly; Secure; Max-Age=60; SameSite=Lax";
            return 302 /;
          }
        EOF
      } : {}
    )
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
