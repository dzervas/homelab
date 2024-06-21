variable "ssh_public_key" {}
variable "domain" {
  default = "dzerv.art"
  type    = string
}

// Oracle Cloud API credentials
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "compartment_ocid" {}
variable "oci_fingerprint" {}
variable "oci_private_key" {}

// Oracle Cloud API Alt credentials
variable "tenancy_ocid_alt" {}
variable "user_ocid_alt" {}
variable "compartment_ocid_alt" {}
variable "oci_fingerprint_alt" {}
variable "oci_private_key_alt" {}

// CloudFlare
variable "cloudflare_email" {}
variable "cloudflare_api_token" {}

// ZeroTier
variable "zerotier_central_token" {}
variable "zerotier_network_id" {}

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
