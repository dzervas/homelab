module "postgres" {
  source = "../docker-service"

  type             = "statefulset"
  name             = "postgres"
  namespace        = var.namespace
  create_namespace = false
  ingress_enabled  = false
  image            = "postgres:16"
  port             = 5432
  retain_pvs       = true
  run_as_user      = 999
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
    POSTGRES_USER = "postgres"
    POSTGRES_DB   = "postgres"
    TZ            = var.timezone
  }

  env_secrets = {
    POSTGRES_PASSWORD = {
      secret = var.password_secret_name
      key    = var.password_secret_key
    }
  }
}
