//resource "consul_key_prefix" "homelab" {
//  datacenter = "home"
//  path_prefix = "homelab/"
//
//  subkeys = {
//    email = "${var.email}"
//    tz = "${var.tz}"
//  }
//}

data "consul_nodes" "home" {
  query_options {
    datacenter = "home"
  }
}

data "nomad_regions" "regions" {}