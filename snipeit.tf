resource "helm_release" "snipeit" {
  name             = "snipeit"
  namespace        = "snipeit"
  create_namespace = true
  atomic           = true

  repository = "https://storage.googleapis.com/t3n-helm-charts"
  chart      = "snipeit"
  version    = "3.4.1"

  values = [file("${path.module}/snipeit-values.yaml")]
}
