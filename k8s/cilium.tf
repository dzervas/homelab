resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.17.1"

  values = [yamlencode({
    devices              = "zt+"
    kubeProxyReplacement = true # Do not use kube-proxy
    autoDirectNodeRoutes = true # Set up routes to pods directly, since the nodes share an L2 network
    operator.replicas    = 1
    ipam.operator = {
      clusterPoolIPv4PodCIDRList = ["10.42.0.0/16"]
      clusterPoolIPv4MaskSize    = 24
    }
  })]
}
