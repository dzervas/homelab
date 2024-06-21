variable "fqdn" {
  type = string
}

variable "region" {
  type = string
}

variable "availability_domain" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "ram_gbs" {
  type    = number
  default = 24
}

variable "disk_gbs" {
  type    = number
  default = 50
}

variable "vnic_subnet_id" {
  type = string
}

variable "image" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "auto_assign_public_ip" {
  description = "Whether to auto-assign a public IP to the instance"
  type        = bool
  default     = true
}

variable "cloudflare_zone_id" {
  type = string
}
