resource "openstack_identity_project_v3" "homelab" {
	name = "homelab"
	description = "HomeLab - Managed by terraform"
	enabled = true
	is_domain = true
}

resource "openstack_dns_zone_v2" "root_zone" {
	name = var.domain
	email = var.email
	description = "Root Zone - Managed by terraform"
	ttl = 60
	type = "PRIMARY"
}
