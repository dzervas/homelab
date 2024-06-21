locals {
  is_arm = strcontains(var.shape, ".A1.")
}

data "template_file" "oracle_k3s" {
  template = file("${path.module}/cloud-init-config.yaml")

  vars = {
    fqdn = "${split("-", var.region)[1]}${var.index}.${var.domain}"
  }
}

resource "oci_core_instance" "k3s" {
  availability_domain = var.availability_domain
  display_name        = "${split("-", var.region)[1]}${var.index}.${var.domain}"
  compartment_id      = var.compartment_ocid
  shape               = var.shape # Free tier allowance

  availability_config {
    is_live_migration_preferred = true
  }

  shape_config {
    ocpus         = var.cpus
    memory_in_gbs = var.ram_gbs
  }

  create_vnic_details {
    subnet_id        = var.vnic_subnet_id
    assign_public_ip = var.auto_assign_public_ip
  }

  source_details {
    source_type             = "image"
    source_id               = var.image
    boot_volume_size_in_gbs = var.disk_gbs
    boot_volume_vpus_per_gb = 120
  }

  #   is_pv_encryption_in_transit_enabled = true
  launch_options {
    # boot_volume_type = "VFIO" # Errors out?
    network_type = "PARAVIRTUALIZED" # Nothing else is supported for ARM
    # remote_data_volume_type = "VFIO" # We don't need this
    is_pv_encryption_in_transit_enabled = local.is_arm
    is_consistent_volume_naming_enabled = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(data.template_file.oracle_k3s.rendered)
    used_for            = "k3s-agent"
  }
  preserve_boot_volume = true
}
