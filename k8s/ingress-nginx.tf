resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # For upgrading: https://github.com/kubernetes/ingress-nginx/releases
  version = "4.10.1"

  values = [yamlencode({
    controller = {
      replicaCount                = 2
      watchIngressWithoutClass    = true
      enableAnnotationValidations = true
      ingressClassResource = {
        default = true
      }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
    }
  })]
}
