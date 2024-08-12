module "mealie" {
  source = "./docker-service"

  type            = "statefulset"
  name            = "cook"
  fqdn            = "cook.${var.domain}"
  ingress_enabled = true
  auth            = "oauth"
  image           = "ghcr.io/mealie-recipes/mealie:v1.10.2"
  port            = 9000
  retain_pvcs     = true
  pvcs = {
    "/app/data" = {
      name         = "data"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
  }

  env = {
    ALLOW_SIGNUP        = "false"
    TZ                  = var.timezone
    BASE_URL            = "http://cook.${var.domain}"
    DAILY_SCHEDULE_TIME = "06:30"

    # OIDC
    # OIDC_AUTH_ENABLED      = "true"
    # OIDC_SIGNUP_ENABLED    = "true"
    # OIDC_CONFIGURATION_URL = "https://auth.dzerv.art/.well-known/openid-configuration"
    # OIDC_CLIENT_ID         = (yamldecode(helm_release.magicentry.values[0])).config.oidc_clients[1].id
    # OIDC_AUTO_REDIRECT     = "true"
    # OIDC_REMEMBER_ME       = "true"
    # OIDC_PROVIDER_NAME     = "Magic ✨"
  }
}
