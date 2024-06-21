resource "cloudflare_record" "instance" {
  zone_id = var.cloudflare_zone_id
  name    = split(".", var.fqdn)[0]
  value   = var.auto_assign_public_ip ? oci_core_instance.k3s.public_ip : oci_core_public_ip.k3s[0].ip_address
  type    = "A"
  proxied = false
  ttl     = 60

  depends_on = [oci_core_instance.k3s]
}