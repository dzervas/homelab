data "cloudflare_zones" "main" {
  filter {
    name = var.domain
  }
}

resource "cloudflare_record" "instance" {
  count = length(module.oci_instances_arm)

  zone_id    = data.cloudflare_zones.main.zones[0].id
  name       = "${split("-", var.region)[1]}${count.index}"
  value      = module.oci_instances_arm[count.index].ip
  type       = "A"
  proxied    = false
  ttl        = 60

  depends_on = [ module.oci_instances_arm ]
}
