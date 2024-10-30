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
        }
      }]
    }

    extraEnv = {
      # Startup commands (can't be done via patching)
      RCON_CMDS_STARTUP = join("\n", var.startup_commands)

      # Mod list
      CURSEFORGE_FILES = join(",", var.curseforge_mods)

      DATAPACKS = join(",", var.datapack_urls)

      MODRINTH_DOWNLOAD_DEPENDENCIES = "required"
      MODRINTH_ALLOWED_VERSION_TYPE  = var.modrinth_allowed_version_type
      MODRINTH_PROJECTS              = join(",", var.modrinth_mods)
      ALLOW_FLIGHT                   = "TRUE"  # Disable flight kick (for tombstone mod)
      SNOOPER_ENABLED                = "FALSE" # Disable telemetry
      INIT_MEMORY                    = var.mem_min
      MAX_MEMORY                     = var.mem_max
      PATCH_DEFINITIONS              = "/patches"
      REMOVE_OLD_DATAPACKS           = "TRUE"
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
        memory = var.mem_min
        cpu    = "1.0"
      }
      limits = {
        memory = var.mem_max
      }
    }

    livenessProbe  = { command = ["curl", "-s", "localhost:19565"] }
    readinessProbe = { command = ["curl", "-s", "localhost:19565"] }

    mcbackup = {
      enabled              = var.backup
      backupInterval       = var.backup_interval
      backupMethod         = "restic"
      rcloneDestDir        = var.namespace
      resticAdditionalTags = "mc_backups ${var.namespace}"
      rcloneConfig         = <<EOT
      [remote]
      type = ${var.rclone_type}
      scope = ${var.rclone_scope}
      root_folder_id = ${var.rclone_root_folder_id}
      token = ${var.rclone_token}
      EOT
      resticRepository     = "remote"
      resticEnvs = {
        RESTIC_PASSWORD = var.restic_password
      }
    }
  })]

  depends_on = [kubernetes_config_map.minecraft_patches]
  lifecycle {
    prevent_destroy = true
  }
}
