resource "kubernetes_namespace" "descheduler" {
  metadata {
    name = "descheduler"
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "helm_release" "descheduler" {
  name       = "descheduler"
  namespace  = kubernetes_namespace.descheduler.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/descheduler"
  chart      = "descheduler"
  version    = "0.30.1"
}
