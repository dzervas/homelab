resource "zerotier_network" "homelab" {
  name        = "HomeLab"
  description = "Managed by Terraform"

  route {
    target = "10.9.8.0/24"
  }

  route {
    target = "10.11.12.0/24"
  }

  enable_broadcast = true
  private          = true
  flow_rules       = "accept;"
}

resource "zerotier_identity" "k3s" {
  count = var.instance_count
}

resource "zerotier_member" "k3s" {
  count                   = var.instance_count
  name                    = "${split("-", var.region)[1]}${count.index}"
  member_id               = zerotier_identity.k3s[count.index].id
  network_id              = var.zerotier_network_id
  description             = "Managed by Terraform"
  ip_assignments          = [ for r in zerotier_network.homelab.route : cidrhost(r.target, 200 + count.index) ]
  allow_ethernet_bridging = true
  hidden                  = false
}

output "zerotier_identities" {
  value = {
    for i, v in zerotier_identity.k3s : oci_core_instance.k3s[i].display_name => { public = v.public_key, private = v.private_key }
  }
  sensitive = true
}
