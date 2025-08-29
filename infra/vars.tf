variable "op_vault" {
  type        = string
  default     = "secrets"
  description = "The vault ID to use for fetching secrets"
  sensitive   = true
}

variable "ssh_public_key" {
  type = string
}

variable "domain" {
  default = "dzerv.art"
  type    = string
}

variable "region" {
  description = "The region to deploy to"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "region_alt" {
  description = "The region to deploy to"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "availability_domain" {
  description = "The availability domain to deploy to"
  type        = string
  default     = "Ogqp:EU-FRANKFURT-1-AD-2"
}

variable "availability_domain_alt" {
  description = "The availability domain to deploy to"
  type        = string
  default     = "zHdw:EU-FRANKFURT-1-AD-3"
}
