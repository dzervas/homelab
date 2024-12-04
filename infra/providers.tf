locals {
  op_secrets = { for section in data.onepassword_item.homelab.section :
    section.label => {
      for field in section.field : field.label => field.value
    }
  }
}

terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-infra"
    }
  }

  required_providers {
    azuread = {
      source = "hashicorp/azuread"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
    oci = {
      source = "oracle/oci"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
    template = {
      source = "hashicorp/template"
    }
    zerotier = {
      source = "zerotier/zerotier"
    }
  }
}

// Secrets
provider "onepassword" {}

data "onepassword_item" "homelab" {
  vault = var.op_vault
  title = "homelab-infra"
}

// Providers
provider "oci" {
  region       = var.region
  auth         = "ApiKey"
  tenancy_ocid = local.op_secrets.oci_main.tenancy_ocid
  user_ocid    = local.op_secrets.oci_main.user_ocid
  fingerprint  = local.op_secrets.oci_main.fingerprint
  private_key  = local.op_secrets.oci_main.private_key
}

provider "oci" {
  alias        = "alt"
  region       = var.region_alt
  auth         = "ApiKey"
  tenancy_ocid = local.op_secrets.oci_alt.tenancy_ocid
  user_ocid    = local.op_secrets.oci_alt.user_ocid
  fingerprint  = local.op_secrets.oci_alt.fingerprint
  private_key  = local.op_secrets.oci_alt.private_key
}

provider "cloudflare" {
  api_token = local.op_secrets.cloudflare.api_token
}

provider "zerotier" {
  zerotier_central_token = local.op_secrets.zerotier.central_token
}

provider "azuread" {
  # Requires `az login` to be run
  tenant_id = local.op_secrets.azuread.tenant_id
}
