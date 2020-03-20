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


resource "openstack_compute_instance_v2" "jira" {
	name = "jira"
	flavor_name = openstack_compute_flavor_v2.nano.name
	image_name = "cirros"
	key_pair = var.key_pair
	security_groups = [ "default" ]

	network {
		name = "guest"
	}
}

resource "openstack_dns_recordset_v2" "jira" {
  zone_id     = openstack_dns_zone_v2.root_zone.id
  name        = "jira.${openstack_dns_zone_v2.root_zone.name}"
  description = "Jira DNS record - Managed by terraform"
  ttl         = 3000
  type        = "A"
  records     = [ openstack_compute_instance_v2.jira.access_ip_v4 ]
}
