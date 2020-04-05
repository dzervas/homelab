resource "consul_acl_token" "vault" {
    description = "Vault Management Token - Managed by Terraform"
    policies = ["global-management"]
}

data "consul_acl_token_secret_id" "vault" {
    accessor_id = consul_acl_token.vault.accessor_id
//    pgp_key = var.pgp_key
}

resource "vault_consul_secret_backend" "main" {
    path = "consul"
    description = "Manages the Consul backend - Managed by Terraform"
    address = "127.0.0.1:8500"
    token = data.consul_acl_token_secret_id.vault.secret_id
}
