data "template_file" "cloud_init_config" {
  count    = var.instance_count
  template = file("${path.module}/cloud-init-config.yaml")

  vars = {
    k3s_token   = var.k3s_token
    k3s_version = var.k3s_version
    k3s_cluster = var.k3s_cluster
    fqdn        = "oracle${count.index}.${var.instance_fqdn_suffix}"
  }
}

resource "oci_core_instance" "k3s_agent" {
  count               = var.instance_count
  availability_domain = var.availability_domain
  display_name        = "oracle${count.index}.${var.instance_fqdn_suffix}"
  compartment_id      = var.compartment_ocid
  shape               = "VM.Standard.A1.Flex" # Free tier allowance

  availability_config {
    is_live_migration_preferred = true
  }

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.k3s.id
    assign_public_ip = false
  }

  source_details {
    source_type             = "image"
    source_id               = var.arm_image_ocid
    boot_volume_size_in_gbs = 150
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(data.template_file.cloud_init_config[count.index].rendered)
    used_for            = "k3s-agent"
  }
}
