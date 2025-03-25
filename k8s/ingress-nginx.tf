locals {
  list_vpn_cidrs = [for cidr in var.vpn_cidrs : "${cidr} 1;"]
}

resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = "ingress"
    labels = {
      # Required due to hostPort
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      managed_by                                   = "terraform"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = kubernetes_namespace_v1.ingress.metadata[0].name
  create_namespace = false
  atomic           = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # For upgrading: https://github.com/kubernetes/ingress-nginx/releases
  version = "4.12.1"

  values = [yamlencode({
    controller = {
      replicaCount = 2

      # TODO: Eliminate this
      allowSnippetAnnotations     = true
      enableAnnotationValidations = true

      watchIngressWithoutClass = true
      ingressClassResource     = { default = true }

      networkPolicy = { enabled = true }

      kind     = "DaemonSet"
      hostPort = { enabled = true }
      # No LB, so no use ClusterIP with host network
      service = { type = "ClusterIP" }

      # hostNetwork = true
      # dnsPolicy   = "ClusterFirstWithHostNet" # Use cluster DNS, even in host network

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

      # nodeSelector = {
      #   "node-role.kubernetes.io/master" = "true"
      # }
    }
  })]
}
