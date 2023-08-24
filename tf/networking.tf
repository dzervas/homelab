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
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 3260
      max = 3260
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 9500
      max = 9500
    }
  }

  # k3s embedded etcd
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 2379
      max = 2380
    }
  }

  # k3s api server
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # k3s flannel VXLAN
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17" # UDP
    udp_options {
      min = 8472
      max = 8472
    }
  }

  # k3s kubelet metrics
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6" # TCP
    tcp_options {
      min = 10250
      max = 10250
    }
  }

  # k3s flannel wireguard-native
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "17" # UDP
    udp_options {
      min = 51820
      max = 51821
    }
  }

  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "1" # ICMP
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
  display_name        = "${split("-", var.region)[1]}${count.index}.${tolist(data.zerotier_network.k3s.dns)[0].domain}"
  lifetime            = "RESERVED"
  private_ip_id       = data.oci_core_private_ips.k3s[count.index].private_ips[0].id
}
