resource "kubernetes_namespace_v1" "openebs" {
  metadata {
    name = "openebs"
    labels = {
      # Required for the hostpath storage class
      "pod-security.kubernetes.io/enforce" = "privileged"
      managed_by                           = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "helm_release" "openebs" {
  name      = "openebs"
  namespace = kubernetes_namespace_v1.openebs.metadata[0].name

  repository = "https://openebs.github.io/openebs"
  chart      = "openebs"
  version    = "4.3.2"
  atomic     = true

  set = [
    # Disable amd64 nodeSelectors - for the life of me, I can't get theme to work in the values
    { name = "mayastor.nodeSelector.kubernetes\\.io/arch", value = "null" },
    { name = "mayastor.io_engine.nodeSelector.kubernetes\\.io/arch", value = "null" },
  ]

  values = [
    yamlencode({
      # Disable the volume snapshot classes CRDs, RKE2 manages this with the rke2-snapshot-controller-crd
      openebs-crds = {
        csi = {
          volumeSnapshot = {
            enabled = false
          }
        }
      }
    }),
    yamlencode({
      # Disable a bunch of services that are not needed

      # Disable LVM & ZFS local (not replicated) charts - disables the dependencies
      # Only maystor & localpv (hostpath for the db) will be installed
      engines = { local = {
        lvm = { enabled = false }
        zfs = { enabled = false }
      } }
      loki     = { enabled = false }
      alloy    = { enabled = false }
      mayastor = { loki-stack = { enabled = false } }
    }),
    yamlencode({
      localpv-provisioner = {
        localpv       = { basePath = "/var/lib/openebs/local" }
        hostpathClass = { reclaimPolicy = "Retain" }
      }

      mayastor = {
        io_engine = {
          # TODO: Fix RDMA
          target = { nvmf = {
            rdma  = { enabled = true }
            iface = "wg0"
          } }

          # The default is 2, which is correct but some nodes have 4 cpus they get saturated
          resources = { requests = { cpu = 1 } }

          tolerations = [{
            key      = "storage-only"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }]
        }

        # Redefine it with reatin by default
        storageClass = { enabled = false }

        nats = {
          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [{
                  matchExpressions = [{
                    key      = "provider"
                    operator = "NotIn"
                    values   = ["homelab"]
                  }]
                }]
              }
            }
            podAntiAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = [{
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/name" = "nats"
                  }
                }
              }]
            }
          }
        }

        # Do not create a new storage class just for etcd, localpv-provisioner is already deployed
        localpv-provisioner = { enabled = false }
        etcd = {
          localpvScConfig = { enabled = false }

          # Use the default hostpath storage class
          persistence = {
            storageClass  = "openebs-hostpath"
            reclaimPolicy = "Retain"
          }

          affinity = {
            nodeAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = {
                nodeSelectorTerms = [{
                  matchExpressions = [{
                    key      = "provider"
                    operator = "NotIn"
                    values   = ["homelab"]
                  }]
                }]
              }
            }
            podAntiAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = [{
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/instance" = "openebs"
                    "app.kubernetes.io/name"     = "etcd"
                  }
                }
              }]
            }
          }
        }
      }
    }),
    yamlencode({
      # Arm64 custom image
      mayastor = {
        image = {
          registry = "ghcr.io/dzervas"
          repo     = "openebs"
        }
        # Fix the initContainers registry
        base = { initContainers = { image = { registry = "docker.io" } } }

        # The default 3.5.6 image is not available in arm64
        etcd = { image = { tag = "3.5-debian-12" } }
      }
    }),
  ]
}

resource "kubernetes_storage_class_v1" "openebs" {
  metadata {
    name = "openebs-replicated"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = true
      "managed_by"                                  = "terraform"
    }
  }

  allow_volume_expansion = true
  storage_provisioner    = "io.openebs.csi-mayastor"
  reclaim_policy         = "Retain"

  parameters = {
    repl = 2
    thin = true
  }
}

# Some openEBS pods run in the host network and they need to be able to reach the etcd pods
# Host networking pods means that they have an IP from a non-k8s CIDR, hence the 0/0 CIDR
resource "kubernetes_network_policy_v1" "openebs_etcd_access" {
  metadata {
    name      = "openebs-etcd-access"
    namespace = helm_release.openebs.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app" = "etcd"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        ip_block {
          # TODO: Use the vpn CIDR instead of 0/0
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 2379 # ETCD port
      }
    }
  }
}

# Same thing for agent-core
resource "kubernetes_network_policy_v1" "openebs_agent_core_access" {
  metadata {
    name      = "openebs-agent-core-access"
    namespace = helm_release.openebs.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app" = "agent-core"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        ip_block {
          # TODO: Use the vpn CIDR instead of 0/0
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        # Agent Core GRPC ports
        port     = 50051
        end_port = 50052
      }
    }
  }
}

# Same thing for io-engine - while it's not exposed through a service, the agnet-core tries
# to connect to it, so we need to allow the connection
resource "kubernetes_network_policy_v1" "openebs_io_engine_access" {
  metadata {
    name      = "openebs-io-engine-access"
    namespace = helm_release.openebs.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app" = "io-engine"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        ip_block {
          # TODO: Use the vpn CIDR instead of 0/0
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 10124 # IO Engine GRPC port - it's hardcorded within the code
      }
    }
  }
}

# Allow `kubectl mayastor` access from the CLI
resource "kubernetes_network_policy_v1" "openebs_api_access" {
  metadata {
    name      = "openebs-api-access"
    namespace = helm_release.openebs.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app" = "api-rest"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = 8081
      }
    }
  }
}

# Not needed since mayastor finds block devices on its own
# TODO: drain & recreate pools
resource "kubernetes_manifest" "openebs_mayastor_diskpool" {
  depends_on = [helm_release.openebs]

  # for_each = toset(["gr0", "gr1", "fra0", "fra1", "srv0"])
  for_each = toset(["gr0", "gr1", "srv0"])

  manifest = {
    apiVersion = "openebs.io/v1beta3"
    kind       = "DiskPool"
    metadata = {
      name      = "${each.key}.${var.domain}"
      namespace = kubernetes_namespace_v1.openebs.metadata[0].name
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      node  = each.key
      disks = ["/dev/mapper/mainpool-storage"]
    }
  }
}

# Node rename (cluster rebuild) notes: https://github.com/openebs/openebs/issues/3775#issuecomment-3068847343


resource "kubernetes_manifest" "opensebs_snapshot_class" {
  manifest = {
    apiVersion = "snapshot.storage.k8s.io/v1"
    kind       = "VolumeSnapshotClass"
    metadata = {
      name = "openebs-replicated"
      annotations = {
        "snapshot.storage.kubernetes.io/is-default-class" = "true"
      }
    }
    driver         = "io.openebs.csi-mayastor"
    deletionPolicy = "Retain"
  }
}
