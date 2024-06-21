data "oci_core_vnic_attachments" "k3s" {
  count          = var.auto_assign_public_ip ? 0 : 1
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.k3s.id

  depends_on = [oci_core_instance.k3s]
}

data "oci_core_private_ips" "k3s" {
  count   = var.auto_assign_public_ip ? 0 : 1
  vnic_id = data.oci_core_vnic_attachments.k3s[0].vnic_attachments[0].vnic_id

  depends_on = [oci_core_instance.k3s]
}


resource "oci_core_public_ip" "k3s" {
  count          = var.auto_assign_public_ip ? 0 : 1
  compartment_id = var.compartment_ocid
  display_name   = var.fqdn
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.k3s[0].private_ips[0].id
}
