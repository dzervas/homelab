locals {
  datapack_names = [for name, values in var.datapacks : name]
  datapack_files = { for name, values in var.datapacks :
    "${name}" => merge(values.data, {
      "pack.mcmeta" = jsonencode({
        pack = {
          pack_format = values.pack_format,
          description = values.description,
        }
      })
    })
  }
}

data "archive_file" "datapacks" {
  for_each = toset(local.datapack_names)

  output_path = "${path.module}/.datapacks/${each.key}.zip"
  type        = "zip"

  dynamic "source" {
    for_each = local.datapack_files[each.key]
    content {
      content  = source.value
      filename = source.key
    }
  }
}

resource "kubernetes_config_map" "datapacks" {
  metadata {
    name      = "datapacks"
    namespace = kubernetes_namespace.minecraft.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  binary_data = { for name, archive in data.archive_file.datapacks :
    "${name}.zip" => filebase64(archive.output_path)
  }
}
