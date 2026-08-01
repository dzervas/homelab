terraform {
  required_providers {
    netbird = {
      source = "registry.terraform.io/netbirdio/netbird"
    }
  }
}

# NB_PAT=(op read 'op://Sites/NetBird DZervArt/pat') tf plan
provider "netbird" {
  management_url = "https://netbird.dzerv.art"
}
