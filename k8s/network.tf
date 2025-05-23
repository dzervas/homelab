data "kubernetes_all_namespaces" "all" {}

resource "kubernetes_network_policy_v1" "default_ingress" {
  for_each = { for ns in data.kubernetes_all_namespaces.all.namespaces : ns => ns if !contains(["kube-system", "ingress"], ns) }
  metadata {
    name      = "default-ingress"
    namespace = each.value
  }
  spec {
    # Applies to all pods
    pod_selector {}
    # Traffic TO the pods
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
    }

    # egress {
      # # Allow intra-namespace traffic
      # to {
        # pod_selector {}
      # }

      # # Allow internet
      # to {
        # ip_block {
          # cidr = "0.0.0.0/0"
        # }
      # }

      # # Allow kube-dns access
      # to {
        # namespace_selector {
          # match_labels = {
            # "kubernetes.io/metadata.name" = "kube-system"
          # }
        # }
        # pod_selector {
          # match_labels = {
            # "k8s-app" = "kube-dns"
          # }
        # }
      # }
    # }
  }
}
