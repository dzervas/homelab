resource "kubernetes_job_v1" "krr" {
  metadata {
    name      = "krr"
    namespace = helm_release.victoriametrics.namespace
  }

  spec {
    template {
      metadata {}

      spec {
        container {
          name    = "krr"
          image   = "robustadev/krr:v1.25.1"
          command = ["/bin/sh", "-c", "python krr.py simple --max-workers 3 --width 255 --use-oomkill-data"]

          resources {
            limits = {
              memory = "2Gi"
            }

            requests = {
              memory = "1Gi"
            }
          }

          image_pull_policy = "Always"
        }

        restart_policy       = "Never"
        service_account_name = kubernetes_service_account_v1.krr_service_account.metadata[0].name
      }
    }
  }

  wait_for_completion = false
}

resource "kubernetes_service_account_v1" "krr_service_account" {
  metadata {
    name      = "krr-service-account"
    namespace = helm_release.victoriametrics.namespace
  }
}

resource "kubernetes_cluster_role_v1" "krr_cluster_role" {
  metadata {
    name = "krr-cluster-role"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["configmaps", "daemonsets", "deployments", "namespaces", "pods", "replicasets", "replicationcontrollers", "services"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["nodes"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["apps"]
    resources  = ["daemonsets", "deployments", "deployments/scale", "replicasets", "replicasets/scale", "statefulsets"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["extensions"]
    resources  = ["daemonsets", "deployments", "deployments/scale", "ingresses", "replicasets", "replicasets/scale", "replicationcontrollers/scale"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "krr_cluster_role_binding" {
  metadata {
    name = "krr-cluster-role-binding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.krr_service_account.metadata[0].name
    namespace = helm_release.victoriametrics.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.krr_cluster_role.metadata[0].name
  }
}
