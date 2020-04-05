data "consul_service" "consul" {
  name = "consul"
}

resource "consul_acl_policy" "proxy" {
  name  = "proxy"
  rules = "node_prefix \"\" { policy = \"read\" } service_prefix \"\" { policy = \"read\" } "
}

resource "consul_acl_token" "proxy" {
  description = "Proxy Discovery Token - Managed by Terraform"
  policies = ["${consul_acl_policy.proxy.name}"]
  local = true
}

data "consul_acl_token_secret_id" "proxy" {
  accessor_id = consul_acl_token.proxy.accessor_id
}

data "template_file" "nomad_proxy_hcl" {
  count = length(data.consul_service.consul.service)
  template = file("${path.module}/nomad/proxy.hcl")
  vars = {
    domain = var.domain
    email = var.email
    tz = var.tz

    // data.consul_service.consul.service.*.port gives 8300, not 8500...
    // TODO: Make this work
//    consul_address = "${element(data.consul_service.consul.service.*.tagged_addresses, count.index).0}:8500"
    consul_address = "10.13.37.80:8500"
    consul_token = data.consul_acl_token_secret_id.proxy.secret_id
  }
}

resource "nomad_job" "proxy" {
  count = length(data.consul_service.consul.service)
  jobspec = element(data.template_file.nomad_proxy_hcl.*.rendered, count.index)
}
