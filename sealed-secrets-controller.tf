resource "helm_release" "sealed_secrets_controller" {
  name      = "sealed-secrets-controller"
  namespace = "kube-system"
  atomic    = true

  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.7.3"
}
