resource "random_password" "affine_db_password" {
  length  = 40
  special = false
}

module "affine" {
  source = "./docker-service"

  type                    = "deployment"
  name                    = "affine"
  ingress_enabled         = true
  auth                    = "mtls"
  fqdn                    = "notes.${var.domain}"
  image                   = "ghcr.io/toeverything/affine-graphql:stable"
  image_pull_policy       = true
  port                    = 3010
  retain_pvs              = true
  enable_security_context = false
  pvs = {
    "/root/.affine" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "10Gi"
      retain       = true
    }
  }

  init_containers = [{
    name    = "migrations"
    image   = "ghcr.io/toeverything/affine-graphql:stable"
    command = ["sh", "-c"]
    args    = ["node ./scripts/self-host-predeploy.js"]
  }]

  env = {
    TZ                         = var.timezone
    REDIS_SERVER_HOST          = "affine-redis"
    DATABASE_URL               = "postgresql://affine:${random_password.affine_db_password.result}@affine-db:5432/affine"
    AFFINE_SERVER_EXTERNAL_URL = "https://notes.${var.domain}"
  }
}


module "affine_redis" {
  source = "./docker-service"

  type                    = "deployment"
  name                    = "affine-redis"
  namespace               = module.affine.namespace
  create_namespace        = false
  ingress_enabled         = false
  image                   = "redis"
  port                    = 6379
  enable_security_context = false
  env = {
    TZ = var.timezone
  }
}


module "affine_db" {
  source = "./docker-service"

  type                    = "statefulset"
  name                    = "affine-db"
  namespace               = module.affine.namespace
  create_namespace        = false
  ingress_enabled         = false
  image                   = "postgres:16"
  port                    = 5432
  retain_pvs              = true
  enable_security_context = false
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
    POSTGRES_USER     = "affine"
    POSTGRES_DB       = "affine"
    POSTGRES_PASSWORD = random_password.affine_db_password.result
    TZ                = var.timezone
  }
}
