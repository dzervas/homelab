module "atuin" {
  source = "./docker-service"

  type            = "deployment"
  name            = "atuin"
  ingress_enabled = false
  image           = "ghcr.io/atuinsh/atuin"
  args            = ["server", "start"]
  port            = 8888

  env = {
    ATUIN_HOST              = "0.0.0.0"
    ATUIN_PORT              = "8888"
    ATUIN_OPEN_REGISTRATION = "false"
    ATUIN_DB_URI = "postgres://atuin:$(ATUIN_DB_PASSWORD)@atuin-db/atuin"
    RUST_LOG     = "info" # "info,atuin_server=debug"
    TZ           = var.timezone
  }

  env_secrets = {
    ATUIN_DB_PASSWORD = {
      secret = "atuin-secrets-op"
      key    = "postgres-password"
    }
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
    POSTGRES_USER = "atuin"
    POSTGRES_DB   = "atuin"
    TZ = var.timezone
  }

  env_secrets = {
    POSTGRES_PASSWORD = {
      secret = "atuin-secrets-op"
      key    = "postgres-password"
    }
  }
}

resource "kubernetes_manifest" "atuin_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "atuin-secrets-op"
      namespace = module.atuin.namespace
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/atuin"
    }
  }
}
