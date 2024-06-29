module "snipeit_ingress" {
  source = "./ingress-block"

  fqdn = "snipeit.${var.domain}"
}

resource "helm_release" "snipeit" {
  name             = "snipeit"
  namespace        = "snipeit"
  create_namespace = true
  atomic           = true

  repository = "https://storage.googleapis.com/t3n-helm-charts"
  chart      = "snipeit"
  version    = "3.4.1"

  values = [yamlencode({
    config = {
      snipeit = {
        url      = "https://snipeit.${var.domain}"
        timezone = var.timezone
        # TODO: Move this to random_string resource
        key = "base64:z54akAQPx9M8x5TTnUp+j2Sh62oDl9/3W8+ZY02TWcc="
      }
    }
    mysql = {
      enabled = true
      persistence = {
        enabled      = true
        storageClass = "longhorn"
        size         = "5Gi"
      }
    }
    persistence = {
      enabled      = true
      storageClass = "longhorn"
      size         = "1Gi"
    }
    ingress = module.snipeit_ingress.host_list
  })]
}
