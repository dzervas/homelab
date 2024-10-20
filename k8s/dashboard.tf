module "dashboard_ingress" {
  source = "./ingress-block"

  fqdn = "dash.${var.domain}"
}

resource "helm_release" "dashboard" {
  name             = "dashboard"
  namespace        = "dashboard"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes.github.io/dashboard"
  chart      = "kubernetes-dashboard"
  version    = "7.5.0"

  values = [yamlencode({
    app = {
      ingress = merge(module.dashboard_ingress.host_list, {
        issuer = {
          # Already taken care of by dashboard_ingress
          scope = "disabled"
        }
        # Expectes an unusual tls map
        tls = {
          enabled    = true
          secretName = "dash-dzerv-art-cert"
        }
      })
    }
  })]
}

resource "kubernetes_service_account_v1" "dashboard_admin" {
  metadata {
    name      = "dashboard-admin"
    namespace = helm_release.dashboard.namespace
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "dashboard_admin" {
  metadata {
    name = "dashboard-admin"
    labels = {
      managed_by = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.dashboard_admin.metadata.0.name
    namespace = kubernetes_service_account_v1.dashboard_admin.metadata.0.namespace
  }
}
