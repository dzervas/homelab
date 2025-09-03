module "trilium" {
  source = "./docker-service"

  type              = "statefulset"
  name              = "trilium"
  image             = "triliumnext/notes:stable"
  image_pull_policy = true
  port              = 8080
  command           = ["node"]
  args              = ["./main.cjs"]

  fqdn = "docs.${var.domain}"
  auth = "mtls"
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size" = "32m" # Also defined in the settings
  }

  retain_pvs = true
  pvs = {
    "/home/node/trilium-data" = {
      name = "data"
      size = "10Gi"
    }
  }
}
