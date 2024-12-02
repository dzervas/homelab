locals {
  vpn_ips = flatten([module.oci_instances_arm[*].vpn_ips, module.oci_instances_arm_alt[*].vpn_ips])
}

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

  dns {
    domain = var.domain
    # TODO: Add the rest of the k8s masters as nameservers
    # servers = concat(["10.9.8.100"], local.vpn_ips)
    servers = ["10.9.8.100"]
  }
}

output "zerotier_identities" {
  value = {
    for v in concat(module.oci_instances_arm, module.oci_instances_arm_alt) : v.name => v.zerotier_identity
  }
  sensitive = true
}
