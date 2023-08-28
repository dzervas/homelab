# Virtual Cloud Network (VCN)
resource "oci_core_vcn" "k3s" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "k3s-vcn"
  dns_label      = "k3svcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "k3s" {
  compartment_id = var.compartment_ocid
  display_name   = "k3s-ig"
  vcn_id         = oci_core_vcn.k3s.id
}

# Route Table
resource "oci_core_route_table" "k3s" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s.id
  display_name   = "k3s-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.k3s.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Security List
resource "oci_core_security_list" "k3s" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.k3s.id
  display_name   = "k3s-sl"

  ingress_security_rules {
    protocol    = "all"
    source      = "0.0.0.0/0"
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

# Subnet
resource "oci_core_subnet" "k3s" {
  availability_domain        = var.availability_domain
  cidr_block                 = "10.0.1.0/24"
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.k3s.id
  display_name               = "k3s-subnet"
  route_table_id             = oci_core_route_table.k3s.id
  security_list_ids          = [oci_core_security_list.k3s.id]
  dns_label                  = "k3ssubnet"
  prohibit_public_ip_on_vnic = false
}

data "oci_core_vnic_attachments" "k3s" {
  count          = length(oci_core_instance.k3s)
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.k3s[count.index].id

  depends_on = [ oci_core_instance.k3s ]
}

data "oci_core_private_ips" "k3s" {
  count = length(oci_core_instance.k3s)
  vnic_id = data.oci_core_vnic_attachments.k3s[count.index].vnic_attachments[0].vnic_id

  depends_on = [ oci_core_instance.k3s ]
}


resource "oci_core_public_ip" "k3s" {
  count               = length(oci_core_instance.k3s)
  compartment_id      = var.compartment_ocid
  display_name        = "${split("-", var.region)[1]}${count.index}.${var.domain}"
  lifetime            = "RESERVED"
  private_ip_id       = data.oci_core_private_ips.k3s[count.index].private_ips[0].id
}