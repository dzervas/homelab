resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"
  values = [yamlencode({
    controller = {
      replicaCount             = 2
      watchIngressWithoutClass = true
      ingressClassResource = {
        default = true
      }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
    }
  })]
}
