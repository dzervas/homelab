data "cloudflare_zones" "main" {
  filter {
    name = var.domain
  }
}
