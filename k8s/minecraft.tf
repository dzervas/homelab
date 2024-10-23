locals {
  minecraft_secrets = { for obj in data.onepassword_item.minecraft.section[0].field : obj.label => obj.value }
}

data "onepassword_item" "minecraft" {
  vault = var.op_vault
  title = "Minecraft"
}

module "minecraft" {
  source             = "./minecraft-server"
  mem_min            = "2G"
  mem_max            = "8G"
  motd               = "I'm a form of art"
  icon               = "https://github.com/dzervas/dzervas/raw/main/assets/images/logo.svg"
  difficulty         = "hard"
  curseforge_api_key = local.minecraft_secrets.cf_api_key
  ops                = ["dzervasgr", "looselyrigorous"]

  whitelist = [
    "dzervasgr",
    "gkaklas",
    "chinesium_",
    "looselyrigorous",

    "quicksilver100", # Reddit guy
    "Raffle_Daffle",  # ortiz
    "Hendog2014",     # ortiz's friend
  ]

  minecraft_version = "1.20.1"
  mod_loader        = "FABRIC"

  startup_commands = [
    "gamerule mobGriefing false",
    "gamerule playersSleepingPercentage 1",
  ]

  curseforge_mods = [
    "backpacked-fabric", "framework-fabric", # Backpacks - needs more storage (defuault 9), disable stealing and require leather instead of rabbit hide

    # Performance/Profiling
    "prometheus-exporter",
    # "spark", # Profiling
  ]
  modrinth_mods = [
    # QoL/Essentials
    "appleskin", # Apple Skin - Hunger preview
    "trinkets",
    "jei",                    # Just Enough Items - Recipe viewer & search
    "ping-wheel",             # Ping with mouse 5
    "xaeros-minimap",         # Minimap (U & Y keybinds to open)
    "convenient-mobgriefing", # Allows to disable mobGriefing but allow farmer breeding
    "universal-graves",       # Item recovery after death (corail-tombstone is broken)

    # Game Mods
    "create-fabric",              # Create - Mechanical contraptions
    "create-goggles",             # Combine goggles with helmets, architectury is a dep
    "create-power-loader-fabric", # Chunk loader, super hard to build one and needs rotational power

    # Data packs
    # "datapack:create-structures"
  ]
  modrinth_allowed_version_type = "beta"
  datapack_urls = [
    "https://mediafilez.forgecdn.net/files/4905/38/backpacked_recipe_fix_datapack.zip",                           # Backpacks recipe uses leather instead of rabbit hide
    "https://cdn.modrinth.com/data/IAnP4np7/versions/GHYR6eCT/Create%20Structures%20-%20v0.1.1%20-%201.20.1.zip", # Create mod structures
  ]

  patches = {
    "backpacked.json" = jsonencode({
      file = "/data/config/backpacked.server.toml"
      ops = [
        { "$set" = { path = "$.pickpocketing.enabledPickpocketing", value = false, value-type = "bool" } },
        { "$set" = { path = "$.backpack.autoEquipOnPickup", value = true, value-type = "bool" } },
      ]
    })
    "universal-graves.json" = jsonencode({
      file = "/data/config/universal-graves/config.json"
      ops = [
        { "$set" = { path = "$.interactions.enable_click_to_open_gui", value = false, value-type = "bool" } },
      ]
    })
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
