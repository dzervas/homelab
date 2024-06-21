module "oci_network_main" {
  source = "./oci-network"
  providers = {
    oci = oci
  }

  compartment_ocid = var.compartment_ocid
}

module "oci_network_alt" {
  source = "./oci-network"
  providers = {
    oci = oci.alt
  }

  compartment_ocid = var.compartment_ocid_alt
}

module "oci_instances_arm" {
  count = 1

  source = "./oci-instance"
  providers = {
    oci = oci
  }

  index                 = 0
  domain                = var.domain
  region                = var.region
  availability_domain   = var.availability_domain
  compartment_ocid      = var.compartment_ocid
  shape                 = "VM.Standard.A1.Flex"
  cpus                  = 4
  ram_gbs               = 24
  disk_gbs              = 150
  vnic_subnet_id        = module.oci_network_main.subnet_id
  image                 = var.arm_image_ocid
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = false
}

module "oci_instances_x86" {
  count = 1

  source = "./oci-instance"
  providers = {
    oci = oci
  }

  index                 = 1
  domain                = var.domain
  region                = var.region
  availability_domain   = var.availability_domain
  compartment_ocid      = var.compartment_ocid
  shape                 = "VM.Standard.E2.1.Micro"
  cpus                  = 1
  ram_gbs               = 1
  disk_gbs              = 50
  vnic_subnet_id        = module.oci_network_main.subnet_id
  image                 = var.x86_image_ocid
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = true
}
