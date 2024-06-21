resource "zerotier_network" "homelab" {
  name        = "HomeLab"
  description = "Managed by Terraform"

  route {
    target = "10.9.8.0/24"
    via    = "10.9.8.1"
  }

  route {
    target = "10.11.12.0/24"
    via    = "10.11.12.1"
  }

  enable_broadcast = true
  private          = true
  flow_rules       = "accept;"
}

resource "zerotier_identity" "k3s" {
  count = length(module.oci_instances_arm) + length(module.oci_instances_x86)
}

resource "zerotier_member" "k3s_arm" {
  count                   = length(module.oci_instances_arm)
  name                    = "${split("-", var.region)[1]}${count.index}"
  member_id               = zerotier_identity.k3s[count.index].id
  network_id              = var.zerotier_network_id
  description             = "Managed by Terraform"
  ip_assignments          = [for r in zerotier_network.homelab.route : cidrhost(r.target, 200 + count.index)]
  allow_ethernet_bridging = true
  hidden                  = false
}

resource "zerotier_member" "k3s_x86" {
  count                   = length(module.oci_instances_x86)
  name                    = "${split("-", var.region)[1]}${count.index + length(module.oci_instances_arm)}"
  member_id               = zerotier_identity.k3s[count.index + length(module.oci_instances_arm)].id
  network_id              = var.zerotier_network_id
  description             = "Managed by Terraform"
  ip_assignments          = [for r in zerotier_network.homelab.route : cidrhost(r.target, 200 + count.index + length(module.oci_instances_arm))]
  allow_ethernet_bridging = true
  hidden                  = false
}

output "zerotier_identities" {
  value = {
    for i, v in zerotier_identity.k3s : concat(module.oci_instances_arm, module.oci_instances_x86)[i].name => { public = v.public_key, private = v.private_key }
  }
  sensitive = true
}

moved {
  from = zerotier_member.k3s
  to   = zerotier_member.k3s_arm
}
