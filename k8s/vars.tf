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

variable "vpn_cidrs" {
  type        = list(string)
  description = "The CIDRs to allow VPN access to the cluster"
  default     = ["10.9.8.0/24", "10.11.12.0/24"]
}
