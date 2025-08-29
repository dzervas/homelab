terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
      version = "~> 7"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 5"
    }
    zerotier = {
      source = "zerotier/zerotier"
      version = "~> 1"
    }
  }
}
