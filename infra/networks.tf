module "oci_network_main" {
  source = "./oci-network"
  providers = {
    oci = oci
  }

  compartment_ocid = local.oci_main.compartment_ocid
}

module "oci_network_alt" {
  source = "./oci-network"
  providers = {
    oci = oci.alt
  }

  compartment_ocid = local.oci_alt.compartment_ocid
}
