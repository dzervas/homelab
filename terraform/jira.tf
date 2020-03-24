resource "openstack_compute_instance_v2" "jira" {
	name = "jira"
	flavor_name = openstack_compute_flavor_v2.medium.name
	image_id = openstack_images_image_v2.ubuntu_18.id
	key_pair = var.key_pair
	security_groups = [ openstack_networking_secgroup_v2.jira.name ]

	network {
		#name = "private"
		name = "guest"
	}

	block_device {
		source_type = "image"
		destination_type = "volume"
		uuid = openstack_images_image_v2.ubuntu_18.id
		volume_size = 10
		boot_index = 0
		delete_on_termination = true
	}
}

resource "openstack_dns_recordset_v2" "jira" {
	zone_id = openstack_dns_zone_v2.root_zone.id
	name = "jira.${openstack_dns_zone_v2.root_zone.name}"
	description = "Jira DNS record - Managed by terraform"
	ttl = 30
	type = "A"
	records = [ openstack_compute_instance_v2.jira.access_ip_v4 ]
}

resource "openstack_networking_secgroup_v2" "jira" {
	name = "jira"
	description = "Jira - Managed by Terraform"
}

resource "openstack_networking_secgroup_rule_v2" "jira_ssh" {
	direction = "ingress"
	ethertype = "IPv4"
	protocol = "tcp"
	port_range_min = 22
	port_range_max = 22
	remote_ip_prefix = "0.0.0.0/0"
	security_group_id = openstack_networking_secgroup_v2.jira.id
}

# Already exists?
#resource "openstack_networking_secgroup_rule_v2" "jira_internet" {
#direction = "egress"
#ethertype = "IPv4"
#remote_ip_prefix = "0.0.0.0/0"
#security_group_id = openstack_networking_secgroup_v2.jira.id
#}
