locals {
  oci_main   = { for obj in data.onepassword_item.oci_main.section[0].field : obj.label => obj.value }
  oci_alt    = { for obj in data.onepassword_item.oci_alt.section[0].field : obj.label => obj.value }
  cloudflare = { for obj in data.onepassword_item.cloudflare.section[0].field : obj.label => obj.value }
  zerotier   = { for obj in data.onepassword_item.zerotier.section[0].field : obj.label => obj.value }
}

terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-infra"
    }
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.13"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
    zerotier = {
      source  = "zerotier/zerotier"
      version = "~> 1.4"
    }
  }
}

// Secrets
provider "onepassword" {}

data "onepassword_item" "oci_main" {
  vault = var.op_vault
  title = "OCI Main"
}

data "onepassword_item" "oci_alt" {
  vault = var.op_vault
  title = "OCI Alt"
}

data "onepassword_item" "cloudflare" {
  vault = var.op_vault
  title = "CloudFlare"
}

data "onepassword_item" "zerotier" {
  vault = var.op_vault
  title = "ZeroTier"
}

// Providers
provider "oci" {
  region       = var.region
  auth         = "ApiKey"
  tenancy_ocid = local.oci_main.tenancy_ocid
  user_ocid    = local.oci_main.user_ocid
  fingerprint  = local.oci_main.fingerprint
  private_key  = local.oci_main.private_key
}

provider "oci" {
  alias        = "alt"
  region       = var.region_alt
  auth         = "ApiKey"
  tenancy_ocid = local.oci_alt.tenancy_ocid
  user_ocid    = local.oci_alt.user_ocid
  fingerprint  = local.oci_alt.fingerprint
  private_key  = local.oci_alt.private_key
}

provider "cloudflare" {
  api_token = local.cloudflare.api_token
}

provider "zerotier" {
  zerotier_central_token = local.zerotier.central_token
}
