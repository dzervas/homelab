locals {
  minecraft_secrets = { for obj in data.onepassword_item.minecraft.section[0].field : obj.label => obj.value }
  minecraft_mem_min = "2G"
  minecraft_mem_max = "8G"
}

data "onepassword_item" "minecraft" {
  vault = var.op_vault
  title = "Minecraft"
}

resource "kubernetes_namespace" "minecraft" {
  metadata {
    name = "minecraft"
    labels = {
      managed_by = "terraform"
    }
  }
}

resource "helm_release" "minecraft" {
  name             = "minecraft"
  namespace        = kubernetes_namespace.minecraft.metadata[0].name
  create_namespace = false
  atomic           = true

  repository = "https://itzg.github.io/minecraft-server-charts/"
  chart      = "minecraft"
  version    = "4.23.2"
  timeout    = 600 # Takes about 5:30 to install a new mod

  # https://github.com/itzg/minecraft-server-charts/blob/master/charts/minecraft/values.yaml
  values = [yamlencode({
    minecraftServer = {
      # Server Info
      eula                     = "TRUE"
      motd                     = "I'm a form of art"
      icon                     = "https://github.com/dzervas/dzervas/raw/main/assets/images/logo.svg"
      onlineMode               = true
      spawnProtection          = 0
      difficulty               = "normal"
      overrideServerProperties = true # Allows to set custom server.properties even after initial setup
      ops                      = "dzervasgr,looselyrigorous"

      # Wipe-related
      type      = "FORGE"
      version   = "1.20.1"
      levelSeed = "31563250179158"

      # Players
      whitelist = join(",", [
        "dzervasgr",
        "gkaklas",
        "chinesium_",
        "looselyrigorous",

        "quicksilver100", # Reddit guy
        "Raffle_Daffle",  # ortiz
        "Hendog2014",     # ortiz's friend
      ])

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

      extraPorts = [{
        name          = "prometheus"
        containerPort = 19565
        protocol      = "TCP"
        service = {
          enabled  = true
          embedded = false # Creates a new service, doesn't merge it to mc's
          type     = "ClusterIP"
          port     = 19565
          annotations = {
            "prometheus.io/scrape" = "true"
            "prometheus.io/path"   = "/"
            "prometheus.io/port"   = "19565"
          }
        }
      }]
    }

    extraEnv = {
      # Startup commands (can't be done via patching)
      RCON_CMDS_STARTUP = join("\n", [
        "gamerule mobGriefing false",
        "gamerule playersSleepingPercentage 1",
      ])

      # Mod list
      CURSEFORGE_FILES = join(",", [
        # Client side: Extreme sound muffler, can mute certain sounds around defined areas
        # For shaders: Embedium, Embedium Extra, Flywheel Compat, Oculus

        # QoL/Essentials
        "appleskin",                # Apple Skin - Hunger preview
        "inventory-sorter",         # Middle click to sort inventory (alts: inventory-bogosorter, inventory-profiles-next)
        "jei",                      # Just Enough Items - Recipe viewer & search
        "ping-wheel",               # Ping with mouse 5
        "xaeros-minimap",           # Minimap (U & Y keybinds to open)
        "more-mobgriefing-options", # Allows to disable mobGriefing but allow farmer breeding
        "zombie-villager-control",  # Zombie Villager Control - Villagers convert 100% on all difficulties and optionally QuickCure
        "gravestone-mod",           # Item recovery after death (corail-tombstone is broken)
        # Find a chest coloring mod
        # Multi-step crafter (queue crafting, stack crafting of weird recipes etc.)
        "backpacked", "curios", "framework", # Backpacks - needs more storage (defuault 9), disable stealing and require leather instead of rabbit hide
        # "beans-backpacks", # Backpacks - it's weird

        # Game Mods
        "create",                             # Create - Mechanical contraptions
        "create-goggles", "architectury-api", # Combine goggles with helmets, architectury is a dep

        # To play/test:
        # "botania", # magic, seems very nice and vanilla-esque
        # "thermal-expansion", # magic/tech
        # "farmers-delight", # more farming & cooking stuff
        # "create-connected", # more create features and QoL stuff
        # "create-easy-structures", or "create-structures" # adds random create mod structures around the world - in alpha
        # "create-diesel-generators", # adds diesel & diesel generator, seems cool, kinda OP?
        # "create-confectionary", # adds various snacks & snack liquids
        # "create-recycle-everything", # recycles stuff. not OP, seems cool
        # "create-power-loader", # loads chunks, needs more research
        # "createaddition", # adds electricity in a balanced way
        # "create-jetpack", # adds jetpacks, like backtank. needs elytra
        # "create-cobblestone", # Adds a balanced cobble generator block to reduce server lag
        # "trackwork", # create mod contraptions-as-vehicles

        # To open to the public:
        # mclink - patreon-based subscription whitelisting
        # open-parties-and-claims - create-compatible claims

        # Performance/Profiling
        "prometheus-exporter",
        "spark", # Profiling
      ])

      DATAPACKS = join(",", [
        "https://mediafilez.forgecdn.net/files/4905/38/backpacked_recipe_fix_datapack.zip" # Backpacks recipe uses leather instead of rabbit hide
      ])

      # MODRINTH_DOWNLOAD_DEPENDENCIES = "required"
      # MODRINTH_PROJECTS = join(",", [ ... ])
      ALLOW_FLIGHT         = "TRUE"  # Disable flight kick (for tombstone mod)
      SNOOPER_ENABLED      = "FALSE" # Disable telemetry
      INIT_MEMORY          = local.minecraft_mem_min
      MAX_MEMORY           = local.minecraft_mem_max
      PATCH_DEFINITIONS    = "/patches"
      REMOVE_OLD_DATAPACKS = "TRUE"
    }

    persistence = {
      labels = {
        "recurring-job.longhorn.io/source"          = "enabled"
        "recurring-job-group.longhorn.io/minecraft" = "enabled"
      }
      dataDir = {
        enabled = true
        Size    = "10Gi"
      }
    }

    # Expose the patches as files
    extraVolumes = [{
      volumeMounts = [{
        name      = kubernetes_config_map.minecraft_patches.metadata[0].name
        mountPath = "/patches/"
        readOnly  = true
      }]
      volumes = [{
        name = kubernetes_config_map.minecraft_patches.metadata[0].name
        configMap = {
          name = kubernetes_config_map.minecraft_patches.metadata[0].name
        }
      }]
    }]

    nodeSelector = {
      "kubernetes.io/hostname" = "gr0.dzerv.art"
    }

    resources = {
      requests = {
        memory = local.minecraft_mem_min
        cpu    = "1.0"
      }
      limits = {
        memory = local.minecraft_mem_max
      }
    }
  })]

  depends_on = [kubernetes_config_map.minecraft_patches]
}

# Config patches
resource "kubernetes_config_map" "minecraft_patches" {
  metadata {
    name      = "patches"
    namespace = kubernetes_namespace.minecraft.metadata[0].name
    labels = {
      managed_by = "terraform"
    }
  }

  # https://docker-minecraft-server.readthedocs.io/en/latest/configuration/interpolating/#patching-existing-files
  data = {
    "moremobgriefingoptions.json" = jsonencode({
      file = "/data/world/serverconfig/moremobgriefingoptions-server.toml"
      ops = [
        # Allow villager turning & breeding
        { "$set" = { path = "$.mobGriefing.minecraft:villager", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:zombie", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:zombie_villager", value = "TRUE" } },

        # Animal growth
        { "$set" = { path = "$.mobGriefing.minecraft:bee", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:cat", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:chicken", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:cow", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:donkey", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:horse", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:sheep", value = "TRUE" } },
        { "$set" = { path = "$.mobGriefing.minecraft:wolf", value = "TRUE" } },
      ]
    })
    "zombievillagercontrol.json" = jsonencode({
      file = "/data/config/zombievillagercontrol-common.toml"
      ops = [
        { "$set" = { path = "$['Zombie Villager Control Config']['Enable QuickCure']", value = true, value-type = "bool" } },
      ]
    })
    "backpacked.json" = jsonencode({
      file = "/data/config/backpacked.server.toml"
      ops = [
        { "$set" = { path = "$.pickpocketing.enabledPickpocketing", value = false, value-type = "bool" } },
        { "$set" = { path = "$.backpack.autoEquipOnPickup", value = true, value-type = "bool" } },
      ]
    })
  }
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
      name        = "minecraft-snpashot"
      cron        = "0 10 * * *" # At 10:00 AM every day
      task        = "snapshot"
      retain      = 14 # 2 Weeks
      concurrency = 1
      groups      = ["minecraft"]
      labels = {
        managed_by = "terraform"
      }
    }
  }
}

resource "kubernetes_manifest" "minecraft_exporter" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "minecraft-exporter"
      namespace = helm_release.prometheus.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      jobLabel = "minecraft"
      selector = {
        matchLabels = {
          "app" = "minecraft-minecraft-prometheus"
        }
      }
      namespaceSelector = {
        matchNames = [kubernetes_namespace.minecraft.metadata[0].name]
      }
      endpoints = [{
        port     = "prometheus"
        interval = "15s"
      }]
    }
  }
}
