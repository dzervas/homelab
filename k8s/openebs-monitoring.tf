resource "helm_release" "openebs_monitoring" {
  name      = "openebs-monitoring"
  namespace = kubernetes_namespace_v1.openebs.metadata[0].name

  repository = "https://openebs.github.io/monitoring/"
  chart      = "monitoring"
  version    = "4.1.0"
  atomic     = true

  values = [yamlencode({
    kube-prometheus-stack = { install = false }
    node-problem-detector = { install = false }
    localpv-provisioner   = { enabled = false }

    openebsMonitoringAddon = {
      lvmLocalPV = { enabled = false }
      zfsLocalPV = { enabled = false }
    }
  })]
}
