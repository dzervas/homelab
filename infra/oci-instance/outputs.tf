output "ip" {
  value = var.auto_assign_public_ip ? oci_core_instance.k3s.public_ip : oci_core_public_ip.k3s[0].ip_address
}

output "name" {
  value = oci_core_instance.k3s.display_name
}
