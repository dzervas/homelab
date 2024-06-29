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
  # For upgrading: https://github.com/kubernetes-sigs/descheduler/releases
  version = "0.30.1"
}
