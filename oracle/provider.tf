terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

provider "oci" {
  # fingerprint          = var.fingerprint
  # private_key          = var.private_key
  # private_key_path     = var.private_key_path
  # private_key_password = var.private_key_password
  region              = var.region
  auth                = "SecurityToken"
  config_file_profile = "terraform"
  # tenancy_ocid         = var.tenancy_ocid
  # user_ocid            = var.user_ocid
}
