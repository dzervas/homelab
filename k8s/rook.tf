resource "kubernetes_namespace_v1" "rook" {
  metadata {
    name = "rook"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "helm_release" "rook" {
  name       = "rook"
  namespace  = kubernetes_namespace_v1.rook.metadata[0].name
  atomic     = true

  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"

  values = [yamlencode({
    # TODO: Migrate the whole cluster
    nodeSelector = {
      "kubernetes.io/hostname" = "gr1.dzerv.art"
    }
    tolerations = [{
      key      = "longhorn"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]

    # Not strictly necessary to enable the rook module,
    # but is a pre-requisite to enable features from it
    enableDiscoveryDaemon = true

    pspEnable: false
    monitoring = {
      enabled = true
    }
  })]
}

module "rook_cluster_ingress" {
  source = "./ingress-block"

  namespace    = helm_release.rook.namespace
  fqdn         = "ceph.${var.domain}"
  mtls_enabled = true
}

resource "helm_release" "rook_cluster" {
  name       = "rook-cluster"
  namespace  = helm_release.rook.namespace
  atomic     = true

  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph-cluster"

  values = [yamlencode({
    # TODO: Migrate the whole cluster
    nodeSelector = {
      "kubernetes.io/hostname" = "gr1.dzerv.art"
    }
    tolerations = [{
      key      = "longhorn"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]

    operatorNamespace = helm_release.rook.namespace

    cephClusterSpec = {
      dashboard = {
        enabled = true
        ssl = false # Disable ceph-side SSL, ingress will take care of it
      }

      mon = {
        count = 1 # TODO: Make that 3
      }
      mgr = {
        count = 1 # TODO: Make that 2?

        modules = [
          { name = "pg_autoscaler", enabled = true }, # Enabled by default but we overwrite it
          { name = "rook", enabled = true }, # Allow ceph to find the rook operator
        ]
      }

      placement = {
        all = {
          tolerations = [{
            key      = "longhorn"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }]
        }
      }

      storage = {
        useAllNodes = false
        useAllDevices = false
        nodes = [
          { name = "gr1.dzerv.art", devices = [{name = "/dev/mainpool/ceph"}] },
        ]
      }
    }

    # TODO: Change default storage class and reclaim policy

    ingress = {
      dashboard = module.rook_cluster_ingress.host_obj_single
    }

    # TODO: cephObjectStores.ingress for external S3?

    pspEnable: false
    monitoring = {
      enabled = true
    }
  })]
}
