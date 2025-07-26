variable "name" {
  type = string
}

variable "namespace" {
  type        = string
  default     = ""
  description = "The namespace to deploy the service in"
}

variable "create_namespace" {
  type    = bool
  default = true
}

variable "fqdn" {
  type        = string
  default     = ""
  description = "The fully qualified domain name for the service"
}

variable "type" {
  type        = string
  description = "The type of service to deploy - deployment or statefulset"
  default     = "statefulset"
  validation {
    condition     = contains(["deployment", "statefulset"], var.type)
    error_message = "Invalid service type. Must be one of deployment or statefulset"
  }
}

variable "port" {
  type        = number
  description = "The container port to expose on the service"
  default     = 80
}

variable "metrics_port" {
  type        = number
  description = "The container port to expose on the service"
  default     = 0
}

variable "metrics_path" {
  type        = string
  description = "The container port to expose on the service"
  default     = "/metrics"
}

variable "metrics_interval" {
  type        = string
  description = "The container port to expose on the service"
  default     = "60s"
}

variable "liveness_http_path" {
  type        = string
  description = "The path to use for liveness probe"
  default     = null
}

variable "readiness_http_path" {
  type        = string
  description = "The path to use for liveness probe"
  default     = null
}

variable "replicas" {
  type    = number
  default = 1
}

variable "node_selector" {
  type        = map(string)
  default     = {}
  description = "A map of node labels to match for the service"
}

variable "image" {
  type        = string
  description = "The container image to deploy"
}

variable "ghcr_image" {
  type        = bool
  default     = false
  description = "Use the global GHCR credentials to pull the image"
}

variable "image_pull_policy" {
  type        = bool
  default     = false
  description = "The container image to deploy"
}

variable "command" {
  type    = list(string)
  default = []
}

variable "args" {
  type    = list(string)
  default = []
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "env_secrets" {
  type = map(object({
    secret = string
    key    = string
  }))
  default = {}
}

variable "ingress_annotations" {
  type    = map(string)
  default = {}
}

variable "config_maps" {
  type        = map(string)
  default     = {}
  description = "A map of config maps to mount in the container in the format { container_path = config_map_name }"
}

variable "secrets" {
  type        = map(string)
  default     = {}
  description = "A map of secrets to mount in the container in the format { container_path = secret_name }"
}

variable "pvs" {
  description = "A map of persistent volumes to mount in the container"
  default     = {}
  type = map(object({
    name         = string
    size         = string
    access_modes = optional(list(string), ["ReadWriteOnce"])
    read_only    = optional(bool, false)
  }))
}

variable "retain_pvs" {
  type    = bool
  default = true
}

variable "ingress_enabled" {
  type    = bool
  default = true
}

variable "auth" {
  type        = string
  description = "The type of external authentiaction to implement - none, mtls or oauth (magicentry)"
  default     = "none"
  validation {
    condition     = contains(["none", "mtls", "oauth"], var.auth)
    error_message = "Invalid auth type. Must be one of none, mtls or oauth"
  }
}

variable "pod_labels" {
  type    = map(string)
  default = {}
}

variable "magicentry_access" {
  type    = bool
  default = false
}

variable "rclone_access" {
  type    = bool
  default = false
}

variable "init_containers" {
  type = list(object({
    name    = string
    image   = string
    command = optional(list(string))
    args    = optional(list(string))
    env     = optional(map(string))
  }))
  default = []
}

variable "enable_security_context" {
  type    = bool
  default = true
}

variable "run_as_user" {
  type    = number
  default = 1000
}
