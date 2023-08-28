variable "ssh_public_key" {}
variable "domain" {
  default = "dzerv.art"
  type = string
}

// Oracle Cloud API credentials
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "compartment_ocid" {}
variable "oci_fingerprint" {}
variable "oci_private_key" {}

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

variable "availability_domain" {
  description = "The availability domain to deploy to"
  type        = string
  default     = "Ogqp:EU-FRANKFURT-1-AD-2"
}

variable "arm_image_ocid" {
  description = "The ARM image OCID to use"
  type        = string
  default     = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaacmd5kkjmy2dxcpaulal2eohsd4xmjkxbjw3pr3gg2kmzomehx4ha"
}
