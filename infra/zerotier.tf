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

output "zerotier_identities" {
  value = {
    # for i, v in zerotier_identity.k3s : concat(module.oci_instances_arm, module.oci_instances_arm_alt)[i].name => { public = v.public_key, private = v.private_key }
    for v in module.oci_instances_arm : v.name => v.zerotier_identity
  }
  sensitive = true
}
