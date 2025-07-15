resource "kubernetes_manifest" "gemini" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChart"

    metadata = {
      name       = "gemini"
      namespace  = "kube-system"
    }

    spec = {
      # For upgrading: https://github.com/FairwindsOps/gemini/releases
      repo    = "https://charts.fairwinds.com/stable"
      chart   = "gemini"
      version = "2.1.3"

      targetNamespace = "gemini"
      createNamespace = true
    }
  }
}

# Restore PVC from snapshot procedure:
# 1. Find the snapshot timestamp with `k get volumesnapshot` (my-pvc-name-<timestamp>)
# 2. Stop the workload (e.g. `k scale all --all --replicas=0`)
# 3. `k annotate snapshotgroup/my-pvc-name --overwrite "gemini.fairwinds.com/restore=<timestamp>"`
# 4. Start the workload with `k scale all --all --replicas=x` or just `tf apply`
