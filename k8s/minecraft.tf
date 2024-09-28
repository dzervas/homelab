# module "snipeit_ingress" {
#   source = "./ingress-block"

#   fqdn = "mc.${var.domain}"
# }
locals {
  minecraft_secrets = { for obj in data.onepassword_item.minecraft.section[0].field : obj.label => obj.value }
}

data "onepassword_item" "minecraft" {
  vault = var.op_vault
  title = "Minecraft"
}

resource "helm_release" "minecraft" {
  name             = "minecraft"
  namespace        = "minecraft"
  create_namespace = true
  atomic           = true

  repository = "https://itzg.github.io/minecraft-server-charts/"
  chart      = "minecraft"
  version    = "4.23.2"

  values = [yamlencode({
    minecraftServer = {
      eula       = "TRUE"
      type       = "FORGE"
      motd       = "I'm a form of art"
      version    = "1.20.1"
      modUrls    = ["https://mediafilez.forgecdn.net/files/5689/514/create-1.20.1-0.5.1.h.jar", "https://mediafilez.forgecdn.net/files/5733/601/tombstone-1.20.1-8.7.4.jar"]
      onlineMode = true
      # whitelist  = ["dzervasgr", "gkaklas", "chinesium_", "looselyrigorous"]
      whitelist = ["dzervasgr"]
      # ops        = ["dzervasgr"]

      autoCurseForge = {
        apiKey = {
          key = local.minecraft_secrets.cf_api_key
        }
      }

      persistence = {
        dataDir = {
          enabled = true
        }
      }
    }
  })]
}
