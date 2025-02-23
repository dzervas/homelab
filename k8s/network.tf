data "kubernetes_all_namespaces" "all" {}

resource "kubernetes_network_policy_v1" "default_ingress" {
  for_each = { for ns in data.kubernetes_all_namespaces.all.namespaces : ns => ns if !contains(["kube-system", "ingress"], ns) }
  metadata {
    name      = "default-ingress"
    namespace = each.value
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      # Allow intra-namespace traffic
      from {
        pod_selector {}
      }

      # Allow ingress-nginx and coredns traffic (maybe kube-dns isn't required?)
      from {
        namespace_selector {
          match_expressions {
            key      = "kubernetes.io/metadata.name"
            operator = "In"
            values   = ["ingress", "kube-system"]
          }
        }
      }

      # Allow ingress-nginx which is in host network mode
      # from {
      #   ip_block {
      #     cidr = "10.42.0.1/32"
      #   }
      # }
    }
  }
}
