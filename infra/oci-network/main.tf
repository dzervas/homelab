# Virtual Cloud Network (VCN)
resource "oci_core_vcn" "network" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "k3s-vcn"
  dns_label      = "k3svcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "network" {
  compartment_id = var.compartment_ocid
  display_name   = "k3s-ig"
  vcn_id         = oci_core_vcn.network.id
}

# Route Table
resource "oci_core_route_table" "network" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.network.id
  display_name   = "k3s-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.network.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "network" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.network.id
  display_name   = "k3s-sl"

  ingress_security_rules {
    protocol = "all"
    source   = "0.0.0.0/0"
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

# Subnet
resource "oci_core_subnet" "network" {
  cidr_block                 = "10.0.1.0/24"
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.network.id
  display_name               = "k3s-subnet"
  route_table_id             = oci_core_route_table.network.id
  security_list_ids          = [oci_core_security_list.network.id]
  dns_label                  = "k3ssubnet"
  prohibit_public_ip_on_vnic = false
}
