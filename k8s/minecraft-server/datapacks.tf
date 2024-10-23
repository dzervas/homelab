locals {
  datapack_names = [for name, values in var.datapacks : name]

  datapack_metadata = { for name, values in var.datapacks :
    "${name}/pack.mcmeta" => jsonencode({
      pack = {
        pack_format = values.pack_format,
        description = values.description,
      }
  }) }

  datapack_files = merge([
    for name, values in var.datapacks : {
      for file, data in values.data : "${name}/${file}" => data
    }
  ]...)
}

# resource "kubernetes_config_map" "datapacks" {
#   metadata {
#     name      = "datapacks"
#     namespace = kubernetes_namespace.minecraft.metadata[0].name
#     labels = {
#       managed_by = "terraform"
#     }
#   }

#   data = merge(local.datapack_metadata, local.datapack_files)
# }
