resource "kubernetes_namespace_v1" "dzervit" {
  metadata {
    name = "dzervit"
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "kubernetes_service_account_v1" "dzervit" {
  metadata {
    name      = "dzervit-sa"
    namespace = kubernetes_namespace_v1.dzervit.metadata.0.name
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "kubernetes_role_v1" "dzervit" {
  metadata {
    name      = "dzervit-admin"
    namespace = kubernetes_namespace_v1.dzervit.metadata.0.name
    labels = {
      managed_by = "terraform"
    }
  }
  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "dzervit" {
  metadata {
    name      = "dzervit-role"
    namespace = kubernetes_namespace_v1.dzervit.metadata.0.name
    labels = {
      managed_by = "terraform"
    }
  }
  role_ref {
    kind      = "Role"
    name      = kubernetes_role_v1.dzervit.metadata.0.name
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.dzervit.metadata.0.name
    namespace = kubernetes_namespace_v1.dzervit.metadata.0.name
  }
}

resource "kubernetes_cluster_role_v1" "pods_lister" {
  metadata {
    name = "pods-lister"
    labels = {
      managed_by = "terraform"
    }
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list"]
  }

}

resource "kubernetes_cluster_role_binding_v1" "dzervit_pods_lister" {
  metadata {
    name = "dzervit-role-pods"
    labels = {
      managed_by = "terraform"
    }
  }
  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.pods_lister.metadata.0.name
    api_group = "rbac.authorization.k8s.io"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.dzervit.metadata.0.name
    namespace = kubernetes_namespace_v1.dzervit.metadata.0.name
  }
}
