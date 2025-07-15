module "audiobookshelf_ingress" {
  source = "./ingress-block"

  namespace    = "audiobookshelf"
  fqdn         = "audiobooks.${var.domain}"
  mtls_enabled = false
  additional_annotations = {
    "cert-manager.io/cluster-issuer"              = "letsencrypt"
    "magicentry.rs/name"                          = "Audiobookshelf"
    "magicentry.rs/realms"                        = "audiobooks,public"
    "magicentry.rs/auth-url"                      = "true"
    "magicentry.rs/manage-ingress-nginx"          = "true"
    "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
    "nginx.ingress.kubernetes.io/proxy-body-size" = "4096m"

    "nginx.ingress.kubernetes.io/auth-url"        = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    "nginx.ingress.kubernetes.io/auth-signin"     = "https://auth.dzerv.art/login"
    # "nginx.ingress.kubernetes.io/auth-url"    = "http://10.11.12.50:8181/auth-url/status"
    # "nginx.ingress.kubernetes.io/auth-signin" = "http://localhost:8181/login"

    "nginx.ingress.kubernetes.io/auth-cache-duration" = "200 202 10m, 401 1m"
    "nginx.ingress.kubernetes.io/auth-cache-key"      = "$remote_user$http_authorization"
  }
}

resource "helm_release" "audiobookshelf" {
  name             = "audiobookshelf"
  namespace        = "audiobookshelf"
  create_namespace = true
  atomic           = true

  repository = "oci://ghcr.io/dzervas/charts"
  chart      = "audiobookshelf"
  version    = "0.2.4"
  values = [yamlencode({
    ingress   = module.audiobookshelf_ingress.host_obj
    podLabels = { "magicentry.rs/enable" = "true" }
    persistence = {
      enabled      = true
      storageClass = "openebs-replicated"
      podcasts = { size = "1Gi" }
      audiobooks = { size = "100Gi" }
    }
  })]
}

resource "kubernetes_network_policy_v1" "audiobookshelf_n8n" {
  metadata {
    name      = "audiobookshelf-n8n"
    namespace = helm_release.audiobookshelf.namespace
  }
  spec {
    pod_selector {}
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
