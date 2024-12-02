locals {
  mtls_annotations = {
    "nginx.ingress.kubernetes.io/auth-tls-secret"        = "cert-manager/client-ca-certificate"
    "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"
    "nginx.ingress.kubernetes.io/auth-tls-verify-client" = var.vpn_bypass_auth ? "optional" : "on"
  }
  oauth_annotations = {
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
  }

  list_vpn_cidrs = [for cidr in var.vpn_cidrs : "${cidr} 1;"]
  vpn_annotations = {
    # "nginx.ingress.kubernetes.io/server-snippet" = <<EOF
    #   map $remote_addr $vpn_client {
    #     default 0;
    #     ${join("\n", local.list_vpn_cidrs)}
    #   }
    # EOF
    # In the case of VPN bypass, we optionally ask for a client cert
    # If it was given and verified, we allow access
    # If not, check if the IP is in the VPN CIDR
    # If it is, allow access, otherwise deny
    # "nginx.ingress.kubernetes.io/configuration-snippet" = <<EOF
    #   map $remote_addr $vpn_client {
    #     default 0;
    #     ${join("\n", local.list_vpn_cidrs)}
    #   }
    #   if ( $ssl_client_verify != SUCCESS ) {
    #     set $auth_tests "non_mtls";
    #   }
    #   if ( $vpn_client != 1 ) {
    #     set $auth_tests "$${auth_tests}_non_vpn";
    #   }

    #   if ( $auth_tests = "non_mtls_non_vpn" ) {
    #     return 403;
    #   }
    # EOF
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
      var.vpn_bypass_auth ? local.vpn_annotations : {},
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
