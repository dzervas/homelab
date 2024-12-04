module "minecraft" {
  source             = "./minecraft-server"
  mem_min            = "4G"
  mem_max            = "12G"
  motd               = "I'm a form of art"
  icon               = "https://github.com/dzervas/dzervas/raw/main/assets/images/logo.svg"
  difficulty         = "normal"
  curseforge_api_key = local.op_secrets.minecraft.curseforge_api_key
  ops = [
    "dzervasgr",
    "looselyrigorous",
    "Raffle_Daffle",
    "Hendog2014",
  ]

  backup          = true
  backup_interval = "6h"
  rclone_values = {
    type                 = "onedrive"
    client_id            = local.op_secrets.rclone.client_id
    client_secret        = local.op_secrets.rclone.client_secret
    drive_type           = "business"
    access_scopes        = "Files.ReadWrite.AppFolder Sites.Read.All offline_access"
    no_versions          = "true"
    hard_delete          = "true"
    av_override          = "true"
    metadata_permissions = "read,write"
    auth_url             = "https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/authorize"
    token_url            = "https://login.microsoftonline.com/${local.op_secrets.rclone.tenancy_id}/oauth2/v2.0/token"
    token                = local.op_secrets.rclone.token
    drive_id             = local.op_secrets.rclone.drive_id
  }
  rclone_path     = "/rclone/backups/minecraft"
  restic_password = local.op_secrets.minecraft.restic_password

  whitelist = [
    "dzervasgr",
    "gkaklas",
    "chinesium_",
    "looselyrigorous",

    "Raffle_Daffle", # ortiz
    "Hendog2014",    # ortiz's friend
    "kingsilicon",
    "KayItzSam",
  ]

  minecraft_version = "1.20.1"
  mod_loader        = "FABRIC"

  startup_commands = [
    "gamerule mobGriefing false",
    "gamerule lenientGriefing true",
    "gamerule witherGriefing false",
    "gamerule dragonGriefing false",
    "gamerule playersSleepingPercentage 1",
  ]

  new_player_items = [
    "minecraft:stone_axe",
    "minecraft:stone_pickaxe",
    "minecraft:crafting_table",
    "minecraft:cooked_porkchop 8",
    "minecraft:bow",
    "minecraft:arrow 64",
  ]

  curseforge_mods = [
    "backpacked-fabric", "framework-fabric", # Backpacks - needs more storage (defuault 9), disable stealing and require leather instead of rabbit hide

    # Performance/Profiling
    "prometheus-exporter", "fabric-api",
  ]
  modrinth_mods = [
    # QoL/Essentials
    "appleskin", # Apple Skin - Hunger preview
    "trinkets",
    "emi",                    # Recipe viewer & search
    "jade",                   # Shows what you point at
    "ping-wheel",             # Ping with mouse 5
    "convenient-mobgriefing", # Allows to disable mobGriefing but allow farmer breeding
    "universal-graves",       # Item recovery after death (corail-tombstone is broken)
    "storagedrawers",         # Storage network to easily access & sort items
    "elytra-slot",            # Be able to wear elytra with armor

    # Game Mods
    "create-fabric",              # Create - Mechanical contraptions
    "create-goggles",             # Combine goggles with helmets, architectury is a dep
    "create-power-loader-fabric", # Chunk loader, super hard to build one and needs rotational power
    "create-garnished",           # Create food stuff
    "create-steam-n-rails",       # More train stuff

    # Decoration
    "chipped", # Tons of new deco blocks

    # Data packs
    # "datapack:create-structures"

    # Optimization
    "lithium", # Pure optimization

    # Server advanced management
    # "kubejs", # Scripting
    "spark", # Profiling
  ]
  modrinth_allowed_version_type = "beta"
  datapack_urls = [
    "https://cdn.modrinth.com/data/IAnP4np7/versions/GHYR6eCT/Create%20Structures%20-%20v0.1.1%20-%201.20.1.zip", # Create mod structures
  ]

  patches = {
    "backpacked-common.json" = jsonencode({
      file = "/data/config/backpacked-common.toml"
      ops = [
        { "$set" = { path = "$.common.backpackInventorySize", value = 3 } },
      ]
    })
    "backpacked-server.json" = jsonencode({
      file = "/data/world/serverconfig/backpacked-server.toml"
      ops = [
        { "$set" = { path = "$.common.pickpocketBackpacks", value = false, value-type = "bool" } },
        { "$set" = { path = "$.common.autoEquipBackpackOnPickup", value = true, value-type = "bool" } },
      ]
    })
    "universal-graves.json" = jsonencode({
      file = "/data/config/universal-graves/config.json"
      ops = [
        { "$set" = { path = "$.interactions.enable_click_to_open_gui", value = false, value-type = "bool" } },
        { "$set" = { path = "$.protection.non_owner_protection_time", value = 604800 } }, # 1 week
        { "$set" = { path = "$.protection.self_destruction_time", value = 604800 } },
      ]
    })
    "storagedrawers.json" = jsonencode({
      file = "/data/config/storagedrawers-common.toml"
      ops = [
        { "$set" = { path = "$.General.debugTrace", value = false, value-type = "bool" } },
      ]
    })
  }

  datapacks = {
    "backpacked_leather" = {
      description = "Backpacked Leather Recipe"
      pack_format = 15
      data = {
        "data/backpacked/recipes/backpack.json" = jsonencode({
          type              = "minecraft:crafting_shaped"
          category          = "misc"
          show_notification = true

          key = {
            H = { item = "minecraft:leather" }
            I = { item = "minecraft:iron_ingot" }
            S = { item = "minecraft:string" }
          }
          pattern = [
            "HHH",
            "SIS",
            "HHH"
          ]

          result = { item = "backpacked:backpack" }
        })
      }
    }
    "cobble_mixer" = {
      description = "Cobblestone mixing recipe"
      pack_format = 15
      data = {
        "data/create/recipes/mixing/cobble_mixer.json" = jsonencode({
          type = "create:mixing"

          heatRequirement = "none"
          ingredients = [
            { fluid = "minecraft:water", amount = 40500 },
            { fluid = "minecraft:lava", amount = 40500 }
          ]

          results = [{ item = "minecraft:cobblestone", count = 64 }]
        })
      }
    }
    "more_wrench_pickups" = {
      description = "More wrench pickups"
      pack_format = 15
      data = {
        "data/create/tags/blocks/wrench_pickup.json" = jsonencode({
          replace = false
          values = [
            "storagedrawers:controller",
            "storagedrawers:controller_slave",
            "storagedrawers:compacting_drawers_2",
            "storagedrawers:compacting_drawers_3",
            "storagedrawers:compacting_half_drawers_2",
            "storagedrawers:compacting_half_drawers_3",
            "#storagedrawers:full_drawers",
            "#storagedrawers:half_drawers",
          ]
        })
      }
    }
  }

  # Client side:
  #  - Extreme sound muffler: can mute certain sounds around defined areas
  #  - Just Enough Items, Breeding, Resources: HUD with item recipes & more. IT'S A MUST.
  #  - Jade: Shows what's in front of you, HP, etc.
  # For shaders in forge: Embeddium, Sodium/Embeddium Extras, Sodium/Embeddium Dynamic Lights, Oculus Flywheel Compat, Oculus
  # For shaders in fabric: Sodium, Sodium Extras, Sodium Dynamic Lights, Indium, Iris Flywheel Compat, Iris

  # Find a chest coloring mod
  # Multi-step crafter (queue crafting, stack crafting of weird recipes etc.)

  # To play/test:
  # "botania", # magic, seems very nice and vanilla-esque
  # "thermal-expansion", # magic/tech
  # "farmers-delight", # more farming & cooking stuff
  # "create-connected", # more create features and QoL stuff
  # "create-easy-structures", or "create-structures" # adds random create mod structures around the world - in alpha
  # "create-diesel-generators", # adds diesel & diesel generator, seems cool, kinda OP?
  # "create-confectionary", # adds various snacks & snack liquids
  # "create-recycle-everything", # recycles stuff. not OP, seems cool
  # "createaddition", # adds electricity in a balanced way
  # "create-jetpack", # adds jetpacks, like backtank. needs elytra
  # "create-cobblestone", # Adds a balanced cobble generator block to reduce server lag
  # "trackwork", # create mod contraptions-as-vehicles

  # To open to the public:
  # mclink - patreon-based subscription whitelisting
  # open-parties-and-claims - create-compatible claims
}
