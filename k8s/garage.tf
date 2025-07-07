resource "kubernetes_namespace_v1" "garage" {
  metadata {
    name = "garage"
    labels = {
      # Required for the host directories
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# module "rook_cluster_ingress" {
#   source = "./ingress-block"
#
#   namespace    = helm_release.garage.namespace
#   fqdn         = "ceph.${var.domain}"
#   mtls_enabled = true
# }

resource "helm_release" "garage" {
  name             = "garage"
  namespace        = kubernetes_namespace_v1.garage.metadata[0].name
  atomic           = true

  # Requires the helm-git plugin:
  # helm plugin install https://github.com/aslafy-z/helm-git
  chart      = "garage"
  repository = "git+https://git.deuxfleurs.fr/Deuxfleurs/garage.git@script/helm?ref=main-v1"

  values = [yamlencode({
    garage = {
      replicationMode  = "2"
      compressionLevel = "3"

      s3 = {
        api = { region = "homelab", rootdomain = ".s3.${var.domain}" }
        web = { index = "index.html", rootdomain = ".app.${var.domain}" }
      }
    }

    # Defaults to amd64-only repo, so use the multi-arch one
    image = { repository = "dxflrs/garage" }

    deployment = { kind = "DaemonSet" }
    monitoring = {
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
    }
  })]
}
