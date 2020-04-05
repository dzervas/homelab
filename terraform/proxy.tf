data "consul_service" "consul" {
	name = "consul"
}

data "template_file" "nomad_proxy_hcl" {
	count = length(data.consul_service.consul.service)
	template = file("${path.module}/nomad/proxy.hcl")
	vars = {
		domain = var.domain
		email = var.email
		tz = var.tz

		consul_address = "${element(data.consul_service.consul.service.*.address, count.index)}:${element(data.consul_service.consul.service.*.port, count.index)}"
	}
}

resource "nomad_job" "proxy" {
	count = length(data.consul_service.consul.service)
	jobspec = element(data.template_file.nomad_proxy_hcl.*.rendered, count.index)
}
