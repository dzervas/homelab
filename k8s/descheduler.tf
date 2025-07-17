resource "kubernetes_manifest" "descheduler" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChart"

    metadata = {
      name      = "descheduler"
      namespace = "kube-system"
    }

    spec = {
      # For upgrading: https://github.com/kubernetes-sigs/descheduler/releases
      repo    = "https://kubernetes-sigs.github.io/descheduler"
      chart   = "descheduler"
      version = "0.33.0"

      targetNamespace = "descheduler"
      createNamespace = true

      valuesContent = yamlencode({
        serviceMonitor = { enabled = true }
      })
    }
  }
}
