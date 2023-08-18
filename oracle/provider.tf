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
    # cloudflare = {
    #   source  = "cloudflare/cloudflare"
    #   version = "~> 2.0"
    # }
  }
}

provider "oci" {
  region              = var.region
  auth                = "SecurityToken"
  config_file_profile = "terraform"
}

# provider "cloudflare" {
#   api_token = var.cloudflare_api_token
# }
