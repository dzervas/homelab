module "invidious_ingress" {
  source = "./ingress-block"

  fqdn = "watch.${var.domain}"
  additional_annotations = {
    # Allow uploading large files - for importing history
    "nginx.ingress.kubernetes.io/proxy-body-size" = "128m"
  }
}

resource "helm_release" "invidious" {
  name             = "invidious"
  namespace        = "watch"
  atomic           = true
  create_namespace = true

  repository = "https://charts-helm.invidious.io"
  chart      = "invidious"
  version    = "2.0.4"

  values = [yamlencode({
    config = {
      hmac_key             = "Twu+zm9XSryHK0RiORQr/1BeKhw"
      domain               = "watch.dzerv.art"
      external_port        = 443
      https_only           = true
      registration_enabled = false
      captcha_enabled      = false
      admins               = ["dzervas"]
    }
    ingress = module.invidious_ingress.host_obj
    # nodeSelector = {
    #   "kubernetes.io/arch" = "arm64"
    # }
    # image = {
    #   tag = "latest-arm64"
    # }
  })]
}
