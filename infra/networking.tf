moved {
  from = oci_core_vcn.k3s
  to   = module.oci_network_main.oci_core_vcn.network
}

moved {
  from = oci_core_internet_gateway.k3s
  to   = module.oci_network_main.oci_core_internet_gateway.network
}

moved {
  from = oci_core_route_table.k3s
  to   = module.oci_network_main.oci_core_route_table.network
}

moved {
  from = oci_core_security_list.k3s
  to   = module.oci_network_main.oci_core_security_list.network
}
moved {
  from = oci_core_subnet.k3s
  to   = module.oci_network_main.oci_core_subnet.network
}
