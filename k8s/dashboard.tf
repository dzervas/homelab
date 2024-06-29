module "dashboard_ingress" {
  source = "./ingress-block"

  fqdn = "dash.${var.domain}"
}

resource "helm_release" "dashboard" {
  name             = "dashboard"
  namespace        = "dashboard"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/dashboard"
  chart      = "kubernetes-dashboard"
  version    = "7.5.0"

  values = [yamlencode({
    app = {
      ingress = merge(module.dashboard_ingress.host_list, {
        issuer = {
          # Already taken care of by dashboard_ingress
          scope = "disabled"
        }
        # Expectes an unusual tls map
        tls = {
          enabled    = true
          secretName = "dash-dzerv-art-cert"
        }
      })
    }
  })]
}
