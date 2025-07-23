# Currently not possible with calico global network policies: https://github.com/projectcalico/calico/issues/6107
data "kubernetes_all_namespaces" "all" {}

resource "kubernetes_network_policy_v1" "default_ingress" {
  # `default` hosts the kubernetes service (kubernetes api)
  # `kube-system` hosts DNS, the actual kube api server, etc.
  for_each = { for ns in data.kubernetes_all_namespaces.all.namespaces : ns => ns if !contains(["kube-system", "ingress", "default"], ns) }
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
            # TODO: Better way to decide what pod these services should have access to
            # ingress-nginx needs to be able to access the services that have an ingress pointing to them
            # prometheus needs to be able to access pods/services that have a service/podmonitor pointing to them
            # A global network policy would be better suited for this
            values = ["ingress", "prometheus"]
          }
        }
      }
    }
  }
}

# resource "kubernetes_network_policy_v1" "default_ingress_system" {
#   # `default` hosts the kubernetes service (kubernetes api)
#   # `kube-system` hosts DNS, the actual kube api server, etc.
#   for_each = toset(["kube-system", "ingress", "default"])
#   metadata {
#     name      = "default-ingress"
#     namespace = each.value
#   }
#   spec {
#     pod_selector {}
#     policy_types = ["Ingress"]
#     ingress {
#       from {
#         namespace_selector {}
#         pod_selector {}
#       }
#     }
#   }
# }

# resource "kubernetes_manifest" "default_np" {
#   manifest = {
#     apiVersion = "crd.projectcalico.org/v1"
#     kind       = "GlobalNetworkPolicy"
#     metadata = {
#       name      = "default"
#     }
#     spec = {
#       # Traffic TO the pods
#       types = ["Ingress"]
#       selector = "all()"
#
#       ingress = [
#         {
#           # `default` hosts the kubernetes service (kubernetes api)
#           # `kube-system` hosts DNS, the actual kube api server, etc.
#           action = "Allow"
#           protocol = "TCP"
#           destination = {
#             namespaceSelector = "projectcalico.org/name in {'default', 'kube-system', 'ingress'}"
#           }
#         },
#         {
#           # Allow traffic from prometheus (to scrape metrics) and ingress-nginx (to route traffic)
#           action = "Allow"
#           protocol = "TCP"
#           source = {
#             namespaceSelector = "projectcalico.org/name in {'ingress', 'prometheus'}"
#           }
#         }
#       ]
#     }
#   }
# }
