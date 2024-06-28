resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.7.1"
  values     = [file("${path.module}/ingress-nginx-values.yaml")]
}
