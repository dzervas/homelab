resource "kubernetes_config_map" "minecraft_patches" {
  metadata {
    name      = "patches"
    namespace = kubernetes_namespace.minecraft.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  # https://docker-minecraft-server.readthedocs.io/en/latest/configuration/interpolating/#patching-existing-files
  data = var.patches
}
