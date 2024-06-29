resource "helm_release" "magicentry" {
  name             = "auth"
  namespace        = kubernetes_namespace.magicentry.metadata[0].name
  create_namespace = true
  atomic           = true

  repository = "oci://ghcr.io/dzervas/charts"
  chart      = "magicentry"
  version    = "0.3.14"
  values     = [file("${path.module}/magicentry-values.yaml")]
}
