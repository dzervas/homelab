resource "kubernetes_namespace_v1" "seaweedfs_operator" {
  metadata {
    name = "seaweedfs-operator"
    labels = {
      # Required for the host directories
      # "pod-security.kubernetes.io/enforce"         = "privileged"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    # prevent_destroy = true
  }
}

resource "helm_release" "seaweedfs-operator" {
  name             = "seaweedfs-operator"
  namespace        = kubernetes_namespace_v1.seaweedfs_operator.metadata[0].name
  # atomic           = true
  # verify           = true

  repository = "https://seaweedfs.github.io/seaweedfs-operator/helm"
  chart      = "seaweedfs-operator"
  # For upgrade: https://github.com/seaweedfs/seaweedfs-operator/blob/master/deploy/helm/Chart.yaml
  version    = "0.1.0"

  values = [yamlencode({
    # Bug https://github.com/seaweedfs/seaweedfs-operator/issues/126
    image = {
      registry = "ghcr.io/seaweedfs"
      tag = "1.0.2"
    }

    serviceMonitor = { enabled = true }

    # To deploy initially set to false and then back to true
    # Otherwise the cert doesn't get created
    webhook = { enabled = false }
  })]
}
