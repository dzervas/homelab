locals {
  fqdn = "watch.${var.domain}"
}

module "invidious_ingress" {
  source = "./ingress-block"

  fqdn = local.fqdn
  additional_annotations = {
    # Allow uploading large files - for importing history
    "nginx.ingress.kubernetes.io/proxy-body-size" = "128m"
  }
}

resource "random_string" "invidious_hmac_key" {
  length = 20
}

resource "helm_release" "invidious" {
  name             = "invidious"
  namespace        = "watch"
  atomic           = true
  create_namespace = true

  repository = "https://charts-helm.invidious.io"
  chart      = "invidious"
  # For upgrading: https://github.com/iv-org/invidious-helm-chart/tree/master/invidious
  version = "2.0.4"

  values = [yamlencode({
    config = {
      hmac_key             = random_string.invidious_hmac_key.result
      domain               = local.fqdn
      external_port        = 443
      https_only           = true
      registration_enabled = false
      captcha_enabled      = false
      admins               = ["dzervas"]
    }
    ingress = module.invidious_ingress.host_obj
    nodeSelector = {
      "kubernetes.io/arch" = "amd64"
    }
  })]
}
