locals {
	fedora_coreos_stable = jsondecode(data.http.fedora_coreos_stable.body).architectures.x86_64.artifacts.openstack
	#fedora_coreos_stable_url = fedora_coreos_stable["architectures"]["x86_64"]["openstack"]["formats"]["qcow2.xz"]["disk"]["location"]
	#fedora_coreos_stable_release = fedora_coreos_stable["architectures"]["x86_64"]["openstack"]["release"]
	fedora_coreos_stable_url = local.fedora_coreos_stable.formats["qcow2.xz"].disk.location
	fedora_coreos_stable_release = local.fedora_coreos_stable.release
}

data "http" "fedora_coreos_stable" {
	url = "https://builds.coreos.fedoraproject.org/streams/stable.json"
}

resource "openstack_images_image_v2" "fedora_coreos_stable" {
	name = "Fedora CoreOS Stable (${local.fedora_coreos_stable_release})"
	image_source_url = local.fedora_coreos_stable_url
	container_format = "bare"
	disk_format = "qcow2"
	visibility = "public"

	properties = {
		os_distro = "coreos"
	}
}

resource "openstack_images_image_v2" "fedora_31" {
	name = "Fedora Cloud 31-1.9"
	image_source_url = "https://download.fedoraproject.org/pub/fedora/linux/releases/31/Cloud/x86_64/images/Fedora-Cloud-Base-31-1.9.x86_64.qcow2"
	container_format = "bare"
	disk_format = "qcow2"
	visibility = "public"
}

resource "openstack_images_image_v2" "ubuntu_18" {
	name = "Ubuntu 18 LTS (Daily build)"
	image_source_url = "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img"
	container_format = "bare"
	disk_format = "qcow2"
	visibility = "public"
}
