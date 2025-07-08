resource "kubernetes_namespace_v1" "openebs" {
  metadata {
    name = "openebs"
    labels = {
      # Required for the hostpath storage class
      "pod-security.kubernetes.io/enforce"         = "privileged"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    # prevent_destroy = true
  }
}

resource "helm_release" "openebs" {
  name             = "openebs"
  namespace        = kubernetes_namespace_v1.openebs.metadata[0].name

  repository = "https://openebs.github.io/openebs"
  chart      = "openebs"
  version    = "4.1.3"
  # atomic     = true

  values = [yamlencode({
    # Disable LVM & ZFS local (not replicated) charts - disables the dependencies
    # Only maystor & localpv (hostpath for the db) will be installed
    engines = {
      local = {
        lvm = { enabled = false }
        zfs = { enabled = false }
      }
    }

    localpv-provisioner = {
      localpv = { basePath = "/var/lib/openebs/local" }
      hostpathClass = { reclaimPolicy = "Retain" }
    }

    mayastor = {
      crds = { enabled = true }
      loki-stack = { enabled = false }
      # Defaults to amd64 nodeSelector, disable it
      # TODO: Remove the root nodeSelector completeley
      # nodeSelector = { "openebs.io/engine" = "mayastor" }
      # io_engine = { nodeSelector = { "openebs.io/engine" = "mayastor" } }

      storageClass = {
        nameSuffix = "replicated"
        default = true
        parameters = {
          repl = 2
          reclaimPolicy = "Retain"
        }
      }

      # TODO: Rename the toleration
      # TODO: Move the toleration
      tolerations = [{
        key      = "longhorn"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }]
      # Disable the tolerations for the rest api
      apis = { rest = { tolerations = [] } }

      # Do not create a new storage class just for etcd, localpv-provisioner is already deployed
      localpv-provisioner = { enabled = false }
      etcd = {
        localpvScConfig = { enabled = false }

        # Use the default hostpath storage class
        persistence = {
          storageClass = "openebs-hostpath"
          reclaimPolicy = "Retain"
        }

        # The default 3.5.6 image is not available in arm64
        image = { tag = "3.5-debian-12" }
      }
    }
  })]
}

# resource "kubernetes_manifest" "openebs_mayastor_diskpool" {
#   depends_on = [helm_release.openebs]
#
#   for_each = toset(["frankfurt0.dzerv.art", "frankfurt1.dzerv.art"])
#
#   manifest = {
#     apiVersion = "openebs.io/v1beta2"
#     kind       = "DiskPool"
#     metadata = {
#       name      = each.key
#       namespace = kubernetes_namespace_v1.openebs.metadata[0].name
#       labels = {
#         managed_by = "terraform"
#       }
#     }
#     spec = {
#       node = each.key
#       disks = [ "/dev/mapper/mainpool-storage" ]
#     }
#   }
# }
