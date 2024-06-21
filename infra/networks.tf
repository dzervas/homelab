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