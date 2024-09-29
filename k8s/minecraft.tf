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
      onlineMode = true
      levelSeed  = "31563250179158"

      whitelist = "dzervasgr,gkaklas,chinesium_,looselyrigorous"
      ops       = "dzervasgr"

      autoCurseForge = {
        apiKey = {
          key = local.minecraft_secrets.cf_api_key
        }
      }
    }

    extraEnv = {
      // Disable flight kick (for tombstone mod)
      ALLOW_FLIGHT     = "TRUE"
      CURSEFORGE_FILES = "create,corail-tombstone,jei,xaeros-minimap"
    }

    persistence = {
      dataDir = {
        enabled = true
      }
    }

    nodeSelector = {
      "kubernetes.io/hostname" = "gr0.dzerv.art"
    }
  })]
}
