terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-k8s"
    }
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.13"
    }
    zerotier = {
      source  = "zerotier/zerotier"
      version = "~> 1.4"
    }
  }
}

provider "oci" {
  region              = var.region
  auth                = "ApiKey"
  tenancy_ocid         = var.tenancy_ocid
  user_ocid = var.user_ocid
  fingerprint = var.oci_fingerprint
  private_key = var.oci_private_key
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "zerotier" {
  zerotier_central_token = var.zerotier_central_token
}
