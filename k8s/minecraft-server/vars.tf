variable "namespace" {
  description = "Namespace to deploy the Minecraft server"
  default     = "minecraft"
  type        = string
}

variable "prometheus_namespace" {
  description = "Namespace to deploy the Minecraft server"
  default     = "prometheus"
  type        = string
}

variable "longhorn_namespace" {
  description = "Namespace to deploy the Minecraft server"
  default     = "longhorn-system"
  type        = string
}

variable "chart_version" {
  description = "Version of the Minecraft server chart"
  default     = "4.23.2"
  type        = string
}

variable "minecraft_version" {
  description = "Version of the Minecraft server"
  default     = "LATEST"
}

variable "mem_min" {
  description = "Minimum memory for the Minecraft server"
  default     = "1Gi"
  type        = string
}

variable "mem_max" {
  description = "Maximum memory for the Minecraft server"
  default     = "2Gi"
  type        = string
}

variable "motd" {
  description = "Message to show in the server browser"
  default     = "Minecraft server"
  type        = string
}

variable "icon" {
  description = "Icon to show in the server browser"
  default     = ""
  type        = string
}

variable "difficulty" {
  description = "Difficulty of the server"
  default     = "normal"
  type        = string

  validation {
    condition     = contains(["peaceful", "easy", "normal", "hard"], var.difficulty)
    error_message = "Difficulty must be one of peaceful, easy, normal, hard"
  }
}

variable "ops" {
  description = "List of players to be operators"
  type        = list(string)
  default     = ["dzervasgr"]
}

variable "whitelist" {
  description = "List of players to be whitelisted"
  type        = list(string)
  default     = []
}

variable "mod_loader" {
  description = "Mod loader to use"
  type        = string

  validation {
    condition     = contains(["VANILLA", "FORGE", "FABRIC", "PAPER", "QUILT"], upper(var.mod_loader))
    error_message = "Possible mod loaders: vanilla, forge, fabric, paper, quilt. For more: https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/"
  }
}

variable "curseforge_api_key" {
  description = "API key for the CurseForge API - Only required if using CurseForge mods"
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = length(var.curseforge_mods) == 0 || (length(var.curseforge_mods) > 0 && length(var.curseforge_api_key) > 0)
    error_message = "To use curseforge mods, please set curseforge_api_key"
  }
}

variable "curseforge_mods" {
  description = "List of CurseForge mods to install"
  type        = list(string)
  default     = []
}

variable "modrinth_mods" {
  description = "List of Modrinth mods to install"
  type        = list(string)
  default     = []
}

variable "modrinth_allowed_version_type" {
  description = "Allowed version type (release, beta, alpha) for the mods from modrinth"
  type        = string
  default     = "release"

  validation {
    condition     = contains(["release", "beta", "alpha"], var.modrinth_allowed_version_type)
    error_message = "Allowed version type must be one of release, beta, alpha"
  }
}

variable "datapack_urls" {
  description = "List of URLs to download datapacks from"
  type        = list(string)
  default     = []
}

variable "startup_commands" {
  description = "List of commands to run on server startup"
  type        = list(string)
  default     = []
}

variable "connect_commands" {
  description = "List of commands to run on player connect"
  type        = list(string)
  default     = []
}

variable "first_connect_commands" {
  description = "List of commands to run on first player connect"
  type        = list(string)
  default     = []
}

variable "last_disconnect_commands" {
  description = "List of commands to run on last player disconnect"
  type        = list(string)
  default     = []
}

variable "new_player_commands" {
  description = "List of commands to run on when a new player joins the server"
  type        = list(string)
  default     = []
}

variable "new_player_items" {
  description = "List of items to give to a new player - use a number to specify the amount (e.g. 'diamond_sword 1')"
  type        = list(string)
  default     = []
}

variable "patches" {
  description = "Map of patches to apply to the server - https://docker-minecraft-server.readthedocs.io/en/latest/configuration/interpolating/#patching-existing-files"
  default     = {}
}

variable "datapacks" {
  description = "Datapacks to define"
  default     = {}
}

variable "backup" {
  description = "Enable backup"
  default     = false
  type        = bool
}

variable "backup_interval" {
  description = "Backup interval"
  default     = "24h"
  type        = string
}

variable "rclone_values" {
  default = {}
  type    = map(any)
}

variable "rclone_path" {
  default = ""
  type    = string
}

variable "restic_password" {
  type      = string
  default   = ""
  sensitive = true

  validation {
    condition     = !var.backup || length(var.restic_password) > 0
    error_message = "To use restic, please set restic_password"
  }
}
