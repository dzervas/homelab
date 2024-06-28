resource "kubernetes_namespace" "dashboard" {
  metadata {
    name = "dashboard"
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "helm_release" "dashboard" {
  name       = "dashboard"
  namespace  = kubernetes_namespace.dashboard.metadata[0].name
  repository = "https://kubernetes.github.io/dashboard"
  chart      = "kubernetes-dashboard"
  version    = "0.30.1"
}
