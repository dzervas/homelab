resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # For upgrading: https://github.com/kubernetes/ingress-nginx/releases
  version = "4.10.1"

  values = [yamlencode({
    controller = {
      replicaCount                = 2
      watchIngressWithoutClass    = true
      enableAnnotationValidations = true
      allowSnippetAnnotations     = true
      ingressClassResource        = { default = true }
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "10254"
      }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
      # 25565 = "minecraft/minecraft-minecraft:25565"
    }
  })]
}
