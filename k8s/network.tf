data "kubernetes_all_namespaces" "all" {}

resource "kubernetes_network_policy_v1" "default_ingress" {
  for_each = { for i, ns in data.kubernetes_all_namespaces.all.namespaces : i => ns if !contains(["kube-system", "ingress"], ns) }
  metadata {
    name      = "default-ingress"
    namespace = each.value
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }

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
  }
}
