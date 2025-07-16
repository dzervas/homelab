resource "helm_release" "garage" {
  name             = "garage"
  namespace        = "garage"
  create_namespace = true
  atomic           = true

  # Requires the helm-git plugin: h plugin install https://github.com/aslafy-z/helm-git (or nixos wrapHelm)
  # For upgrading: https://git.deuxfleurs.fr/Deuxfleurs/garage/releases
  repository = "git+https://git.deuxfleurs.fr/Deuxfleurs/garage.git@script/helm?ref=v2.0.0"
  # chart      = "git+https://git.deuxfleurs.fr/Deuxfleurs/garage.git@script/helm?ref=v2.0.0"
  chart      = "garage"
  version    = "0.8.0"

  values = [yamlencode({
    garage = {
      replicationFactor = "1" # OpenEBS takes care of replication
      compressionLevel  = "3"

      s3 = {
        api = { region = "homelab", rootdomain = ".s3.${var.domain}" }
        web = { index = "index.html", rootdomain = ".app.${var.domain}" }
      }
    }

    deployment = { replicaCount = "1" }

    # Defaults to amd64-only repo, so use the multi-arch one
    image = { repository = "dxflrs/garage" }

    monitoring = {
      metrics = {
        serviceMonitor = { enabled = true }
      }
    }
  })]
}
