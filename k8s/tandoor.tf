data "onepassword_item" "tandoor_secret" {
  vault = var.onepassword_vault
  title = "tandoor"
}

module "tandoor" {
  source = "./docker-service"

  type            = "statefulset"
  name            = "meals"
  fqdn            = "meals.${var.domain}"
  ingress_enabled = true
  auth            = "oauth"
  image           = "vabene1111/recipes:1.5.18"
  port            = 8080
  retain_pvcs     = true
  pvcs = {
    "/opt/recipes/staticfiles" = {
      name         = "staticfiles"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
    "/opt/recipes/mediafiles" = {
      name         = "mediafiles"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "5Gi"
      retain       = true
    }
    "/opt/recipes/db" = {
      name         = "db"
      read_only    = false
      access_modes = ["ReadWriteOnce"]
      size         = "1Gi"
      retain       = true
    }
  }

  env = {
    TZ               = var.timezone
    DB_ENGINE        = "django.db.backends.sqlite3"
    DB_NAME          = "/opt/recipes/db/db.sqlite3"
    SECRET_KEY       = data.onepassword_item.tandoor_secret.password
    SOCIAL_PROVIDERS = "allauth.socialaccount.providers.openid_connect"
    SOCIALACCOUNT_PROVIDERS = jsonencode({
      openid_connect = {
        APPS = [{
          name        = "Magic ✨"
          provider_id = "magicentry"
          client_id   = (yamldecode(helm_release.magicentry.values[0])).config.oidc_clients[2].id
          secret      = (yamldecode(helm_release.magicentry.values[0])).config.oidc_clients[2].secret
          settings = {
            server_url = "http://magicentry.auth.svc.cluster.local:8080"
          }
        }]
      }
    })
  }
}
