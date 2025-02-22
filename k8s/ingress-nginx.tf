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

      config = {
        http-snippet = <<EOF
          geo $vpn_client {
            default 0;
            ${join("\n", local.list_vpn_cidrs)}
          }
        EOF
      }

      nodeSelector = {
        "node-role.kubernetes.io/master" = "true"
      }
    }
    tcp = {
      2222 = "borgserver/borgserver-service:2222"
    }
  })]
}

resource "kubernetes_network_policy_v1" "ingress-nginx-pod-ingress" {
  metadata {
    name      = "ingress-nginx-pod-ingress"
    namespace = helm_release.ingress_nginx.namespace
  }

  spec {
    policy_types = ["Ingress"]
    pod_selector {
      match_labels = {
        enable-ingress = "true"
      }
    }
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "ingress-nginx"
          }
        }
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "ingress-nginx-pod-" {
  metadata {
    name      = "ingress-nginx-pod-egress"
    namespace = helm_release.ingress_nginx.namespace
  }

  spec {
    policy_types = ["Egress"]
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "ingress-nginx"
      }
    }
    egress {
      to {
        pod_selector {
          match_labels = {
            enable-ingress = "true"
          }
        }
      }
    }
  }
}
