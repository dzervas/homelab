locals {
  zones = [
    "modem",
    "hass",
  ]
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.domain
  }
}
