module "oci_instances_arm" {
  count = 1

  source = "./oci-instance"
  providers = {
    oci = oci
  }

  fqdn                  = "${split("-", var.region)[1]}${count.index}.${var.domain}"
  apex_record           = false
  wildcard_record       = true
  region                = var.region
  availability_domain   = var.availability_domain
  compartment_ocid      = local.op_secrets.oci_main.compartment_ocid
  shape                 = "VM.Standard.A1.Flex"
  cpus                  = 4
  ram_gbs               = 24
  disk_gbs              = 200
  vnic_subnet_id        = module.oci_network_main.subnet_id
  image                 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaacmd5kkjmy2dxcpaulal2eohsd4xmjkxbjw3pr3gg2kmzomehx4ha"
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = false

  cloudflare_zone_id = data.cloudflare_zones.main.zones[0].id

  zerotier_index      = 200 + count.index
  zerotier_network_id = zerotier_network.homelab.id
  zerotier_routes     = zerotier_network.homelab.route
}

module "oci_instances_arm_alt" {
  count = 1

  source = "./oci-instance"
  providers = {
    oci = oci.alt
  }

  fqdn                  = "${split("-", var.region)[1]}${count.index + length(module.oci_instances_arm)}.${var.domain}"
  apex_record           = false
  wildcard_record       = true
  region                = var.region_alt
  availability_domain   = var.availability_domain_alt
  compartment_ocid      = local.op_secrets.oci_alt.compartment_ocid
  shape                 = "VM.Standard.A1.Flex"
  cpus                  = 4
  ram_gbs               = 24
  disk_gbs              = 200
  vnic_subnet_id        = module.oci_network_alt.subnet_id
  image                 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa7je5yvlqunoi2mxr3vlvg5ua2wn3bxbncsxbc25mbcptjthlbqyq"
  ssh_public_key        = var.ssh_public_key
  auto_assign_public_ip = false

  cloudflare_zone_id = data.cloudflare_zones.main.zones[0].id

  zerotier_index      = 200 + count.index + length(module.oci_instances_arm)
  zerotier_network_id = zerotier_network.homelab.id
  zerotier_routes     = zerotier_network.homelab.route
}
