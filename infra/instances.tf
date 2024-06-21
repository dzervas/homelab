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
  image                 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaacmd5kkjmy2dxcpaulal2eohsd4xmjkxbjw3pr3gg2kmzomehx4ha"
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = false
}

module "oci_instances_arm_alt" {
  count = 1

  source = "./oci-instance"
  providers = {
    oci = oci.alt
  }

  index                 = 1
  domain                = var.domain
  region                = var.region_alt
  availability_domain   = var.availability_domain_alt
  compartment_ocid      = var.compartment_ocid_alt
  shape                 = "VM.Standard.A1.Flex"
  cpus                  = 4
  ram_gbs               = 24
  disk_gbs              = 200
  vnic_subnet_id        = module.oci_network_alt.subnet_id
  image                 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa7je5yvlqunoi2mxr3vlvg5ua2wn3bxbncsxbc25mbcptjthlbqyq"
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = false
}
