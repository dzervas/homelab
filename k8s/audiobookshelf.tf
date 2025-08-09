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

    "nginx.ingress.kubernetes.io/auth-url"    = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    "nginx.ingress.kubernetes.io/auth-signin" = "https://auth.${var.domain}/login"
    # "nginx.ingress.kubernetes.io/auth-url"    = "http://100.100.50.5:8181/auth-url/status"
    # "nginx.ingress.kubernetes.io/auth-signin" = "http://localhost:8181/login"

    "nginx.ingress.kubernetes.io/auth-cache-duration" = "200 202 10m"
    # XXX: add cookie to avoid cache takeover from the NAT gateway
    "nginx.ingress.kubernetes.io/auth-cache-key" = "$remote_user$http_authorization"
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
      podcasts     = { size = "1Gi" }
      audiobooks   = { size = "100Gi" }
    }
  })]
}

module "audiobookrequest" {
  source = "./docker-service"

  type  = "statefulset"
  name  = "audiobookrequest"
  fqdn  = "add.audiobooks.${var.domain}"
  auth  = "mtls"
  image = "markbeep/audiobookrequest"
  port  = 8000

  namespace        = helm_release.audiobookshelf.namespace
  create_namespace = false

  pvs = {
    "/config" = {
      name = "config"
      size = "512Mi"
    }
  }

  env = {
    TZ = var.timezone
  }
}
