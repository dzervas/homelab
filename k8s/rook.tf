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
    tolerations = [{
      key      = "longhorn"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]

    toolbox = { enabled = true }
    operatorNamespace = helm_release.rook.namespace

    cephClusterSpec = {
      dashboard = {
        enabled = true
        ssl = false # Disable ceph-side SSL, ingress will take care of it
      }

      mgr = {
        modules = [
          { name = "pg_autoscaler", enabled = true }, # Enabled by default but we overwrite it
          { name = "rook", enabled = true }, # Allow ceph to find the rook operator
        ]
      }

      mon = { allowMultiplePerNode = false }

      placement = {
        mgr = {
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
          { name = "frankfurt1.dzerv.art", devices = [{name = "/dev/mainpool/ceph"}] },
        ]
      }
    }

    # TODO: Change default storage class and reclaim policy
    # cephBlockPools = [{
    #   name = "ceph-blockpool"
    #   spec = {
    #     replicated = { size = 2 }
    #   }
    #   storageClass = {
    #     enabled = true
    #     name = "ceph-block"
    #     isDefault = true
    #     reclaimPolicy = "Retain"
    #     allowVolumeExpansion = true
    #     volumeBindingMode = "Immediate"
    #   }
    # }]

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
