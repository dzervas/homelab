resource "openstack_compute_flavor_v2" "nano" {
	name = "t1.nano"
	vcpus = 1
	ram = 128
	disk = 1
	swap = 0
	is_public = true
}

resource "openstack_compute_flavor_v2" "micro" {
	name = "t1.micro"
	vcpus = 1
	ram = 256
	disk = 2
	swap = 0
	is_public = true
}

resource "openstack_compute_flavor_v2" "small" {
	name = "t1.small"
	vcpus = 1
	ram = 512
	disk = 10
	swap = 1
	is_public = true
}

resource "openstack_compute_flavor_v2" "medium" {
	name = "t1.medium"
	vcpus = 1
	ram = 1024
	disk = 20
	swap = 2
	is_public = true
}

resource "openstack_compute_flavor_v2" "large" {
	name = "t1.large"
	vcpus = 2
	ram = 2048
	disk = 20
	swap = 2
	is_public = true
}

resource "openstack_compute_flavor_v2" "xlarge" {
	name = "t1.xlarge"
	vcpus = 2
	ram = 4096
	disk = 20
	swap = 4
	is_public = true
}
