locals {
  list_vpn_cidrs = [for cidr in var.vpn_cidrs : "${cidr} 1;"]
}

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
      replicaCount = 2

      allowSnippetAnnotations     = true
      enableAnnotationValidations = true

      watchIngressWithoutClass = true
      ingressClassResource     = { default = true }

      kind        = "DaemonSet"
      hostNetwork = true
      hostPort    = { enabled = true }
      dnsPolicy   = "ClusterFirstWithHostNet" # Use cluster DNS, even in host network
      # No LB, so no use ClusterIP with host network
      service = { type = "ClusterIP" }

      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "10254"
      }

      # config = {
      #   http-snippet = <<EOF
      #     geo $vpn_client {
      #       default 0;
      #       ${join("\n", local.list_vpn_cidrs)}
      #     }
      #   EOF
      # }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
    }
  })]
}
