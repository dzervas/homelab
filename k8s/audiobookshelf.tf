module "audiobookshelf_ingress" {
  source = "./ingress-block"

  fqdn         = "audiobooks.${var.domain}"
  mtls_enabled = false
  additional_annotations = {
    "cert-manager.io/cluster-issuer"              = "letsencrypt"
    "magicentry.rs/realms"                        = "audiobooks,public"
    "magicentry.rs/auth-url"                      = "true"
    "magicentry.rs/manage-ingress-nginx"          = "true"
    "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
    "nginx.ingress.kubernetes.io/proxy-body-size" = "4096m"
    "nginx.ingress.kubernetes.io/auth-url"        = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    "nginx.ingress.kubernetes.io/auth-signin"     = "https://auth.dzerv.art/login"
    "nginx.ingress.kubernetes.io/server-snippet"  = <<EOF
      location = /__magicentry_auth_code {
        add_header Set-Cookie "code=$arg_code; Path=/; HttpOnly; Secure; Max-Age=60; SameSite=Lax";
        return 302 /;
      }
    EOF
  }
}

resource "helm_release" "audiobookshelf" {
  name             = "audiobookshelf"
  namespace        = "audiobookshelf"
  create_namespace = true
  atomic           = true

  repository = "oci://ghcr.io/dzervas/charts"
  chart      = "audiobookshelf"
  version    = "0.2.1"
  values = [yamlencode({
    ingress = module.audiobookshelf_ingress.host_obj
    persistence = {
      enabled      = true
      storageClass = "longhorn"
      podcasts = {
        size       = "1Gi"
        volumeName = "pvc-1f03a6a2-865f-445e-aba5-7ac5cecdcb96"
      }
      audiobooks = {
        size       = "100Gi"
        volumeName = "pvc-5e0c0003-1d57-4939-8cc7-ca8eb3932942"
      }
      config   = { volumeName = "pvc-617d3ebd-694e-46fb-b58d-8f32c2bd1446" }
      metadata = { volumeName = "pvc-9ad70fb5-9d33-4883-8401-8e7297b46798" }
    }
  })]
}