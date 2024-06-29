resource "helm_release" "sealed_secrets_controller" {
  name      = "sealed-secrets-controller"
  namespace = "kube-system"
  atomic    = true

  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  # For upgrading: https://github.com/bitnami-labs/sealed-secrets/blob/main/RELEASE-NOTES.md
  version = "2.16.0"
}
