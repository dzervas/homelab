resource "helm_release" "invidious" {
  name             = "invidious"
  namespace        = "watch"
  atomic           = true
  create_namespace = true

  repository = "https://charts-helm.invidious.io"
  chart      = "invidious"
  version    = "2.0.4"

  values = [file("${path.module}/invidious-values.yaml")]
}
