data "cloudflare_zones" "main" {
  filter {
    name = tolist(data.zerotier_network.k3s.dns)[0].domain
  }
}

resource "cloudflare_record" "instance" {
  count = length(oci_core_instance.k3s)

  zone_id    = data.cloudflare_zones.main.zones[0].id
  name       = "${split("-", var.region)[1]}${count.index}"
  value      = oci_core_public_ip.k3s[count.index].ip_address
  type       = "A"
  proxied    = false
  ttl        = 60

  depends_on = [ oci_core_public_ip.k3s ]
}
