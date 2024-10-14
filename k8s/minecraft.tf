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
      # TODO: Add a mechanism for patch files to be applied on startup (https:#docker-minecraft-server.readthedocs.io/en/latest/configuration/interpolating/#patching-existing-files)
      eula       = "TRUE"
      type       = "FORGE"
      motd       = "I'm a form of art"
      icon       = "https://github.com/dzervas/dzervas/raw/main/assets/images/logo.svg"
      onlineMode = true

      version   = "1.20.1"
      levelSeed = "31563250179158"

      spawnProtection          = 0
      difficulty               = "normal"
      overrideServerProperties = true # Allows to set custom server.properties even after initial setup

      whitelist = "dzervasgr,gkaklas,chinesium_,looselyrigorous"
      ops       = "dzervasgr"

      autoCurseForge = {
        apiKey = {
          key = local.minecraft_secrets.cf_api_key
        }
      }

      # Needed for RCON startup commands to work
      rcon = {
        # Since we don't expose the service from ingress, we're safe
        enabled               = true
        withGeneratedPassword = true
      }
    }

    extraEnv = {
      ALLOW_FLIGHT    = "TRUE"  # Disable flight kick (for tombstone mod)
      SNOOPER_ENABLED = "FALSE" # Disable telemetry
      INIT_MEMORY     = "1G"
      MAX_MEMORY      = "4G"
      RCON_CMDS_STARTUP = join("\n", [
        "gamerule mobGriefing false",
        "gamerule playersSleepingPercentage 1",
        "mobgriefing minecraft:villager true",
      ])
      CURSEFORGE_FILES = join(",", [
        # QoL/Essentials
        "appleskin",                # Apple Skin - Hunger preview
        "advanced-compass",         # Compass with coordinates (to find others, etc.)
        "inventory-sorter",         # Middle click to sort inventory (alts: inventory-bogosorter, inventory-profiles-next)
        "jei",                      # Just Enough Items - Recipe viewer & search
        "ping-wheel",               # Ping with mouse 5
        "xaeros-minimap",           # Minimap (U & Y keybinds to open)
        "more-mobgriefing-options", # Allows to disable mobGriefing but allow farmer breeding
        # Find a chest coloring mod
        # Multi-step crafter (queue crafting, stack crafting of weird recipes etc.)

        # Game Mods
        "create",                             # Create - Mechanical contraptions
        "create-goggles", "architectury-api", # Combine goggles with helmets, architectury is a dep

        # To play/test:
        # "botania", # magic, seems very nice and vanilla-esque
        # "thermal-expansion", # magic/tech
        # "farmers-delight", # more farming & cooking stuff
        # "create-easy-structures", # adds random create mod structures around the world - in alpha
        # "create-diesel-generators", # adds diesel & diesel generator, seems cool, kinda OP?
        # "create-confectionary", # adds various snacks & snack liquids
        # "create-recycle-everything", # recycles stuff. not OP, seems cool
        # "create-power-loader", # loads chunks, needs more research
        # "createaddition", # adds electricity in a balanced way
        # "create-jetpack", # adds jetpacks, like backtank. needs elytra

        # Item recovery after death (corail-tombstone is broken)
        "gravestone-mod",
      ])
    }

    persistence = {
      labels = {
        "recurring-job-group.longhorn.io/minecraft" = "enabled"
      }
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

# To enable the job for the PVC:
# kubectl -n minecraft label pvc/<the pvc> recurring-job-group.longhorn.io/minecraft=enabled
resource "kubernetes_manifest" "minecraft_snapshot_task" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "minecraft-snpashot"
      namespace = helm_release.longhorn.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      name = "minecraft-snpashot"
      cron = "0 10 * * *" # At 10:00 AM every day
      task = "snapshot"
      retain = 14 # 2 Weeks
      concurrency = 1
      groups = ["minecraft"]
      labels = {
        managed_by = "terraform"
      }
    }
  }
}
