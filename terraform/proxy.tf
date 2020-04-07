// Allow Consul Catalog Access
resource "consul_acl_policy" "allow_catalog" {
  name  = "allow_catalog"
  rules = "node_prefix \"\" { policy = \"read\" } service_prefix \"\" { policy = \"read\" } "
  description = "Allow Catalog read access"
}

// Generate the token
// TODO: Store in vault
resource "consul_acl_token" "proxy_catalog_tf" {
  description = "Proxy Catalog Discovery Token - Managed by Terraform"
  policies = ["${consul_acl_policy.allow_catalog.name}"]
  local = true
}

data "consul_acl_token_secret_id" "proxy_catalog_tf" {
  accessor_id = consul_acl_token.proxy_catalog_tf.accessor_id
}

resource "consul_intention" "proxy" {
  source_name = "proxy-traefik"
  destination_name = "proxy-acme-dns-api"
  action = "allow"
}

resource "nomad_job" "proxy" {
  jobspec = templatefile("${path.module}/nomad/proxy.nomad", {
    tz = var.tz
    email = var.email
    domain = var.domain
    // TODO: Remove hardcoded address
    consul_address = var.consul_address
    consul_token = data.consul_acl_token_secret_id.proxy_catalog_tf.secret_id
  })
}
