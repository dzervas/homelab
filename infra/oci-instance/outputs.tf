output "ip" {
  value = oci_core_public_ip.k3s.ip_address
}

output "name" {
  value = oci_core_instance.k3s.display_name
}
