resource "random_password" "atuin_db_password" {
  length  = 40
  special = false
}

module "atuin" {
  source = "./docker-service"

  type            = "deployment"
  name            = "atuin"
  fqdn            = "sh.${var.domain}"
  ingress_enabled = false
  image           = "ghcr.io/atuinsh/atuin"
  args            = ["server", "start"]
  port            = 8888

  env = {
    ATUIN_HOST              = "0.0.0.0"
    ATUIN_PORT              = "8888"
    ATUIN_OPEN_REGISTRATION = "false"
    ATUIN_DB_URI            = "postgres://atuin:${random_password.atuin_db_password.result}@atuin-db/atuin"
    RUST_LOG                = "info,atuin_server=debug"
    TZ                      = var.timezone
  }
}

module "atuin_db" {
  source = "./docker-service"

  type                    = "statefulset"
  name                    = "atuin-db"
  namespace               = module.atuin.namespace
  create_namespace        = false
  ingress_enabled         = false
  image                   = "postgres:14"
  port                    = 5432
  enable_security_context = false
  retain_pvs              = true
  pvs = {
    "/var/lib/postgresql" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
  }

  env = {
    POSTGRES_USER     = "atuin"
    POSTGRES_DB       = "atuin"
    POSTGRES_PASSWORD = random_password.atuin_db_password.result
    TZ                = var.timezone
  }
}
