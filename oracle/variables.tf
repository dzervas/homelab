variable "ssh_public_key" {}

// Oracle Cloud API credentials
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "compartment_ocid" {}

variable "instance_count" {
  description = "The number of instances to deploy"
  type        = number
  default     = 1
}

variable "k3s_token" {
  description = "The token used to join the cluster"
  type        = string
}
variable "k3s_version" {
  description = "The k3s version to install"
  type        = string
}
variable "k3s_cluster" {
  description = "The k3s cluster endpoint"
  type        = string
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

variable "instance_fqdn_suffix" {
  description = "The instance FQDN suffix"
  type        = string
  default     = "k8s.dzervas.gr"
}
