resource "openstack_images_image_v2" "ubuntu_18" {
	name = "Ubuntu 18 LTS (Daily build)"
	image_source_url = "https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img"
	container_format = "bare"
	disk_format = "qcow2"
	visibility = "public"
}
