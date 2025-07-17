module "atuin" {
  source = "./docker-service"

  type            = "statefulset"
  name            = "atuin"
  ingress_enabled = false
  image           = "ghcr.io/atuinsh/atuin"
  args            = ["server", "start"]
  port            = 8888

  env = {
    ATUIN_HOST              = "0.0.0.0"
    ATUIN_PORT              = "8888"
    ATUIN_OPEN_REGISTRATION = "false"

    ATUIN_DB_URI = "sqlite:///db/atuin.db"
    RUST_LOG     = "info" # "info,atuin_server=debug"
    TZ           = var.timezone
  }

  pvs = {
    "/db" = {
      name         = "db"
      size         = "1Gi"
      retain       = true
    }
  }
}
