variable "op_vault" {
  type        = string
  default     = "secrets"
  description = "The vault ID to use for fetching secrets"
  sensitive   = true
}

variable "ssh_public_key" {}
variable "domain" {
  default = "dzerv.art"
  type    = string
}

variable "instance_count" {
  description = "The number of instances to deploy"
  type        = number
  default     = 1
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

variable "arm_image_ocid" {
  description = "The ARM image OCID to use"
  type        = string
  # Canonical-Ubuntu-22.04-Minimal-aarch64-2024.05.31-0
  default = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa7je5yvlqunoi2mxr3vlvg5ua2wn3bxbncsxbc25mbcptjthlbqyq"
}

variable "x86_image_ocid" {
  description = "The x86 image OCID to use"
  type        = string
  # Canonical-Ubuntu-22.04-Minimal-2024.05.31-0
  default = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaaew5licvc3purkupr5rcwxxplgfvewpalcoyqd7om6nz42vcn3ofq"
}
