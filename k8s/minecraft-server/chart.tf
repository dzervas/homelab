locals {
  rclone_config = join("\n", [for key, value in var.rclone_values : "${key} = ${value}"])
}

resource "random_password" "rcon_password" {
  length  = 40
  special = false
}

resource "helm_release" "minecraft" {
  name             = "minecraft"
  namespace        = kubernetes_namespace.minecraft.metadata[0].name
  create_namespace = false
  atomic           = true

  repository = "https://itzg.github.io/minecraft-server-charts/"
  chart      = "minecraft"
  version    = var.chart_version
  timeout    = 600 # Takes about 5:30 to install a new mod

  # https://github.com/itzg/minecraft-server-charts/blob/master/charts/minecraft/values.yaml
  values = [yamlencode({
    minecraftServer = {
      # Server Info
      eula                     = "TRUE"
      motd                     = var.motd
      icon                     = var.icon
      onlineMode               = true
      spawnProtection          = 0
      difficulty               = var.difficulty
      overrideServerProperties = true # Allows to set custom server.properties even after initial setup
      ops                      = join(",", var.ops)
      serviceType              = "NodePort"
      nodePort                 = 25565
      maxTickTime              = -1 # Don't crash on slow tickrate
      viewDistance             = 32

      # Wipe-related
      type    = var.mod_loader
      version = var.minecraft_version

      # Players
      whitelist = join(",", var.whitelist)

      autoCurseForge = {
        apiKey = {
          key = var.curseforge_api_key
        }
      }

      modrinth = {
        projects           = var.modrinth_mods
        allowedVersionType = var.modrinth_allowed_version_type
      }

      # Needed for RCON startup commands to work
      rcon = {
        enabled  = true
        password = random_password.rcon_password.result
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
        }
      }]
    }

    extraEnv = {
      # Startup commands (can't be done via patching)
      RCON_CMDS_STARTUP = join("\n", var.startup_commands)
      RCON_CMDS_ON_CONNECT = join("\n", concat(var.connect_commands, [
        "team join new @a[team=]",
        join("\n", var.new_player_commands),
        join("\n", [for item in var.new_player_items : "give @a[team=new] ${item}"]),
        "team join old @a[team=new]",
      ]))
      RCON_CMDS_FIRST_CONNECT   = join("\n", var.first_connect_commands)
      RCON_CMDS_LAST_DISCONNECT = join("\n", var.last_disconnect_commands)

      # Mod list
      CURSEFORGE_FILES               = join(",", var.curseforge_mods)
      MODRINTH_DOWNLOAD_DEPENDENCIES = "optional"

      DATAPACKS = join(",", concat(var.datapack_urls, [for name in local.datapack_names : "/datapacks/${name}.zip"]))

      ALLOW_FLIGHT         = "TRUE"  # Disable flight kick (for tombstone mod)
      SNOOPER_ENABLED      = "FALSE" # Disable telemetry
      INIT_MEMORY          = var.mem_min
      MAX_MEMORY           = var.mem_max
      PATCH_DEFINITIONS    = "/patches"
      REMOVE_OLD_DATAPACKS = "TRUE"
      SIMULATION_DISTANCE  = "16"
      SYNC_CHUNK_WRITES    = "FALSE"
      DISABLE_HEALTHCHECK  = "TRUE"
    }

    persistence = {
      storageClass = "local-path"
      dataDir = {
        enabled = true
        Size    = "10Gi"
      }
    }

    extraVolumes = [{
      volumeMounts = [
        # Expose the patches as files
        {
          name      = kubernetes_config_map.minecraft_patches.metadata[0].name
          mountPath = "/patches/"
          readOnly  = true
        },

        # Expose the datapacks as files
        {
          name      = kubernetes_config_map.datapacks.metadata[0].name
          mountPath = "/datapacks/"
          readOnly  = true
        },
      ]
      volumes = [
        {
          name = kubernetes_config_map.minecraft_patches.metadata[0].name
          configMap = {
            name = kubernetes_config_map.minecraft_patches.metadata[0].name
          }
        },
        {
          name = kubernetes_config_map.datapacks.metadata[0].name
          configMap = {
            name = kubernetes_config_map.datapacks.metadata[0].name
          }
        },
      ]
    }]

    nodeSelector = {
      "kubernetes.io/hostname" = "gr0.dzerv.art"
    }

    resources = {
      requests = {
        memory = var.mem_min
        cpu    = "1.0"
      }
      limits = {
        memory = var.mem_max
        cpu    = "4.0"
      }
    }

    livenessProbe = {
      command             = ["true"]
      initialDelaySeconds = 1
      periodSeconds       = 20
      failureThreshold    = 30
    }
    readinessProbe = {
      command             = ["true"]
      initialDelaySeconds = 1
      periodSeconds       = 20
      failureThreshold    = 30
    }

    mcbackup = {
      enabled              = var.backup
      backupInterval       = var.backup_interval
      backupMethod         = "restic"
      initialDelay         = "2h"
      rcloneDestDir        = var.namespace
      resticAdditionalTags = "mc_backups ${var.namespace}"
      rcloneRemote         = "remote"
      rcloneConfig         = <<EOT
      [remote]
      ${local.rclone_config}
      EOT
      resticRepository     = "rclone:remote:${var.rclone_path}"
      resticEnvs = {
        RESTIC_PASSWORD = var.restic_password
      }
      extraEnv = {
        PRE_SAVE_ALL_SCRIPT = <<EOT
          rcon-cli tellraw @a '[{"text":"Server will lag/time out in "},{"text":"30 seconds","bold":true,"underlined":true,"color":"yellow"},{"text":" to take backup"}]'
          sleep 30
          rcon-cli say 'Server saving the world to start the backup'
        EOT
        PRE_BACKUP_SCRIPT   = "rcon-cli say 'Done, starting backup. Lag should stop'"
        POST_BACKUP_SCRIPT  = "rcon-cli say 'Backup done!'"
      }
    }
  })]

  depends_on = [kubernetes_config_map.minecraft_patches]
  lifecycle {
    prevent_destroy = true
  }
}
