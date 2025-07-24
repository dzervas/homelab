module "rclone" {
  source = "./docker-service"

  type  = "deployment"
  name  = "rclone"
  fqdn  = "webdav.${var.domain}"
  auth  = "mtls"
  image = "rclone/rclone:1"
  port  = 80

  command = ["rclone"]
  args = [
    "serve", "webdav", "remote:",
    "--cache-dir", "/tmp/.cache",
    # VFS Cache results in a horrible performance drop for round-trip write-read operations
    "--vfs-cache-mode", "full",
    "--addr", "0.0.0.0:80",
    "--config", "/secret/rclone.conf"
  ]

  secrets = {
    "/secret" = kubernetes_manifest.rclone_secrets_op.manifest.metadata.name
  }
}

resource "kubernetes_manifest" "rclone_secrets_op" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "rclone-secrets-op"
      namespace = module.rclone.namespace
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [{ extract = { key = "rclone" } }]
    }
  }
}
