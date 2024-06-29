variable "name" {
  type = string
}

variable "fqdn" {
  type        = string
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

variable "replicas" {
  type    = number
  default = 1
}

variable "image" {
  type        = string
  description = "The container image to deploy"
}

variable "args" {
  type    = list(string)
  default = []
}

variable "config_maps" {
  type        = map(string)
  default     = {}
  description = "A map of config maps to mount in the container in the format { container_path = config_map_name }"
}

variable "pvcs" {
  type = map(object({
    name         = string
    size         = string
    access_modes = list(string)
    retain       = bool
    read_only    = bool
  }))
}

variable "retain_pvcs" {
  type    = bool
  default = true
}

variable "ingress_enabled" {
  type    = bool
  default = true
}

variable "mtls_enabled" {
  type    = bool
  default = true
}
