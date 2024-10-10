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
  timeout    = 600 # Takes about 5:30 to install a new mod

  values = [yamlencode({
    minecraftServer = {
      // NOTE: Needs:
      // /gamerule mobGriefing false (disable creeper explosions and endermen picking up blocks)
      // /gamerule playersSleepingPercentage 1 (skip night if 1 player is sleeping)
      // Patch file in config/tombstone-server.toml decorative_grave.prayer_cooldown = 10 (Ankh takes too long to recharge, 10m is good)
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
      ALLOW_FLIGHT = "TRUE" // Disable flight kick (for tombstone mod)
      CURSEFORGE_FILES = join(",", [
        // QoL/Essentials
        "appleskin",        // Apple Skin - Hunger preview
        "advanced-compass", // Compass with coordinates (to find others, etc.)
        "inventory-sorter", // Middle click to sort inventory (alts: inventory-bogosorter, inventory-profiles-next)
        "jei",              // Just Enough Items - Recipe viewer & search
        "ping-wheel",       // Ping with mouse 5
        "xaeros-minimap",   // Minimap (U & Y keybinds to open)

        // Game Mods
        "create", // Create - Mechanical contraptions
        "create-goggles", "architectury-api", // Combine goggles with helmets, architectury is a dep

        // To play/test:
        // "botania", // magic, seems very nice and vanilla-esque
        // "thermal-expansion", // magic/tech
        // "farmers-delight", // more farming & cooking stuff
        // "create-easy-structures", // adds random create mod structures around the world - in alpha
        // "create-diesel-generators", // adds diesel & diesel generator, seems cool, kinda OP?
        // "create-confectionary", // adds various snacks & snack liquids
        // "create-recycle-everything", // recycles stuff. not OP, seems cool
        // "create-power-loader", // loads chunks, needs more research
        // "createaddition", // adds electricity in a balanced way
        // "create-jetpack", // adds jetpacks, like backtank. needs elytra

        // Item recovery after death (corail-tombstone is broken)
        "gravestone-mod",
      ])
    }

    persistence = {
      dataDir = {
        enabled = true
        Size    = "10Gi"
      }
    }

    nodeSelector = {
      "kubernetes.io/hostname" = "gr0.dzerv.art"
    }
  })]
}
