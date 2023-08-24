data "template_file" "oracle_k3s" {
  count    = var.instance_count
  template = file("${path.module}/cloud-init-config.yaml")

  vars = {
    fqdn = "${split("-", var.region)[1]}${count.index}.${tolist(data.zerotier_network.k3s.dns)[0].domain}"
  }
}

resource "oci_core_instance" "k3s" {
  count               = var.instance_count
  availability_domain = var.availability_domain
  display_name        = "${split("-", var.region)[1]}${count.index}.${tolist(data.zerotier_network.k3s.dns)[0].domain}"
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
    boot_volume_vpus_per_gb = 120
  }

  is_pv_encryption_in_transit_enabled = true
  launch_options {
    # boot_volume_type = "VFIO" # Errors out?
    network_type = "PARAVIRTUALIZED" # Nothing else is supported for ARM
    # remote_data_volume_type = "VFIO" # We don't need this
    is_pv_encryption_in_transit_enabled = true
    is_consistent_volume_naming_enabled = true
  }

  # Not supported on ARM
  # platform_config {
  #   type = "regular"
  #   is_measured_boot_enabled = true
  #   is_secure_boot_enabled = true
  #   is_trusted_platform_module_enabled = true
  #   is_memory_encryption_enabled = true
  # }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(data.template_file.oracle_k3s[count.index].rendered)
    used_for            = "k3s-agent"
  }
  preserve_boot_volume = true
}
