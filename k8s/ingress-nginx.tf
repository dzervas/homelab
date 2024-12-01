resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # For upgrading: https://github.com/kubernetes/ingress-nginx/releases
  version = "4.11.3"

  values = [yamlencode({
    controller = {
      replicaCount                = 2
      watchIngressWithoutClass    = true
      enableAnnotationValidations = true
      allowSnippetAnnotations     = true
      # hostPort                    = { enabled = true }
      # hostNetwork                 = true
      # dnsPolicy                   = "ClusterFirstWithHostNet" # Recommended for hostNetwork
      ingressClassResource = { default = true }
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "10254"
      }
      service = {
        externalTrafficPolicy = "Local"
      }

      # ConfigMap data
      config = {
        # use-proxy-protocol = "true"
        # real-ip-header     = "proxy_protocol"
        enable-real-ip             = "true"
        proxy-real-ip-cidr         = "10.42.0.0/16"
        compute-full-forwarded-for = "true"
        use-forwarded-headers      = "false"
        real-ip-header             = "proxy_protocol"
      }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
    }
  })]
}
