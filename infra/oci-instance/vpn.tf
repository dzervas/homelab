resource "zerotier_identity" "instance" {}

resource "zerotier_member" "instance" {
  name                    = split(".", var.fqdn)[0]
  member_id               = zerotier_identity.instance.id
  network_id              = var.zerotier_network_id
  description             = "Managed by Terraform"
  ip_assignments          = [for r in var.zerotier_routes : cidrhost(r.target, var.zerotier_index)]
  allow_ethernet_bridging = true
  hidden                  = false
}
