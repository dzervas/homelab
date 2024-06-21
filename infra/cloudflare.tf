data "cloudflare_zones" "main" {
  filter {
    name = var.domain
  }
}

resource "cloudflare_record" "arm_instances" {
  count = length(module.oci_instances_arm)

  zone_id = data.cloudflare_zones.main.zones[0].id
  name    = "${split("-", var.region)[1]}${count.index}"
  value   = module.oci_instances_arm[count.index].ip
  type    = "A"
  proxied = false
  ttl     = 60

  depends_on = [module.oci_instances_arm]
}

resource "cloudflare_record" "x86_instances" {
  count = length(module.oci_instances_x86)

  zone_id = data.cloudflare_zones.main.zones[0].id
  name    = "${split("-", var.region)[1]}${count.index + length(module.oci_instances_arm)}"
  value   = module.oci_instances_x86[count.index].ip
  type    = "A"
  proxied = false
  ttl     = 60

  depends_on = [module.oci_instances_arm]
}

moved {
  from = cloudflare_record.instance
  to   = cloudflare_record.arm_instances
}
