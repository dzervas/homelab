terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-infra"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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

provider "aws" {
  alias      = "info"
  region     = var.aws_region_info
  access_key = var.aws_access_key_info
  secret_key = var.aws_secret_key_info
}

provider "oci" {
  region       = var.region
  auth         = "ApiKey"
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.oci_fingerprint
  private_key  = var.oci_private_key
}

provider "oci" {
  alias        = "alt"
  region       = var.region_alt
  auth         = "ApiKey"
  tenancy_ocid = var.tenancy_ocid_alt
  user_ocid    = var.user_ocid_alt
  fingerprint  = var.oci_fingerprint_alt
  private_key  = var.oci_private_key_alt
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "zerotier" {
  zerotier_central_token = var.zerotier_central_token
}
