resource "helm_release" "rook" {
  name       = "rook"
  namespace  = "rook"
  create_namespace = true
  atomic     = true

  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = "v1.17.5"

  values = [yamlencode({
    # TODO: Migrate the whole cluster
    nodeSelector = {
      "kubernetes.io/hostname" = "gr1.dzerv.art"
    }
    tolerations = [{
      key      = "longhorn"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]

    pspEnable: false
    monitoring = {
      enabled = true
    }
  })]
}
