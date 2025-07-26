module "rclone" {
  source = "./docker-service"

  type  = "deployment"
  name  = "rclone"
  fqdn  = "webdav.${var.domain}"
  auth  = "mtls"
  image = "rclone/rclone:1"
  port  = 80

  metrics_port = 9090

  liveness_http_path  = "/"
  readiness_http_path = "/"

  command = ["sh", "-c"]
  args = [join(" ", [
    "rclone", "serve", "webdav", "remote:",
    "--cache-dir", "/tmp/.cache",
    # VFS Cache results in a horrible performance drop for round-trip write-read operations
    "--vfs-cache-mode", "full",
    "--addr", "0.0.0.0:80",
    "--config", "/secret/rclone.conf",
    "--temp-dir", "/tmp",
    "--metrics-addr", "0.0.0.0:9090",
  ])]

  secrets = {
    "/secret" = "${kubernetes_manifest.rclone_secrets_op.manifest.metadata.name}:rw"
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
