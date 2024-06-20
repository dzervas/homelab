data "oci_core_vnic_attachments" "k3s" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.k3s.id

  depends_on = [ oci_core_instance.k3s ]
}

data "oci_core_private_ips" "k3s" {
  vnic_id = data.oci_core_vnic_attachments.k3s.vnic_attachments[0].vnic_id

  depends_on = [ oci_core_instance.k3s ]
}


resource "oci_core_public_ip" "k3s" {
  compartment_id      = var.compartment_ocid
  display_name        = "${split("-", var.region)[1]}${var.index}.${var.domain}"
  lifetime            = "RESERVED"
  private_ip_id       = data.oci_core_private_ips.k3s.private_ips[0].id
}
