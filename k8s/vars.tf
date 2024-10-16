variable "domain" {
  type    = string
  default = "dzerv.art"
}

variable "timezone" {
  type        = string
  description = "The default timezone to use"
  default     = "Europe/Athens"
}

variable "op_vault" {
  type        = string
  default     = "secrets"
  description = "The vault ID to use for fetching secrets"
  sensitive   = true
}
