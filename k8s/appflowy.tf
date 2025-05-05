resource "helm_release" "appflowy" {
  name             = "appflowy"
  namespace        = "appflowy"
  repository       = "https://khorshuheng.github.io/appflowy-self-host-resources"
  chart            = "appflowy"
  version          = "0.1.29"
  atomic           = true
  create_namespace = true

  values = [yamlencode({
    global = {
      scheme = "https"
      externalHost = "notes.${var.domain}"
      ingress = {
        nginx = {
          extraAnnotations = {
            "cert-manager.io/cluster-issuer"     = "letsencrypt"
            "magicentry.rs/name"                 = "AppFlowy"
            "magicentry.rs/realms"               = "notes"
            "magicentry.rs/auth-url"             = "true"
            "magicentry.rs/manage-ingress-nginx" = "true"

            "nginx.ingress.kubernetes.io/ssl-redirect" = "true"

            "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
            "nginx.ingress.kubernetes.io/auth-tls-secret"        = "appflowy/client-ca"
            "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"

            "nginx.ingress.kubernetes.io/proxy-body-size" = "4096m"
          }
        }
      }
      smtp = {
        host = "smtp-hve.office365.com"
        port = 587
        user = "notes@dzerv.art"
        email = "notes@dzerv.art"
        tlsKind = "wrapper"
      }
      gotrue = {
        adminEmail = "dzervas@dzervas.gr"
      }
      s3 = {
        bucket = "notes"
        minioUrl = "http://rclone.rclone.svc.cluster.local"
      }
      secret = {
        name = "appflowy-secrets-op"
        create = false
      }
    }
    minio = { enabled = false }
    postgresql = {
      auth = { existingSecret = "appflowy-secrets-op" }
    }
  })]
}

resource "kubernetes_manifest" "appflowy_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "appflowy-secrets-op"
      namespace = "appflowy"
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/atuin"
    }
  }
}
