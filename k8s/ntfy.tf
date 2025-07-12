module "ntfy" {
  source = "./docker-service"

  type              = "deployment"
  name              = "ntfy"
  image             = "binwiederhier/ntfy"
  args              = ["serve"]
  image_pull_policy = true
  port              = 8080

  fqdn              = "notify.${var.domain}"
  auth              = "mtls"

  pvs = {
    "/var/cache/ntfy" = {
      name = "cache"
      size = "128Mi"
    }
  }

  env = {
    NTFY_BASE_URL = "https://notify.${var.domain}"
    NTFY_BEHIND_PROXY = "true"
    NTFY_CACHE_DURATION = "96h" # keep undelivered notifications for 4 days
    NTFY_LISTEN_HTTP = ":8080"
    NTFY_WEB_PUSH_FILE = "/var/cache/ntfy/webpush.db"
  }

  env_secrets = {
    NTFY_WEB_PUSH_PUBLIC_KEY = {
      secret = "ntfy-op"
      key    = "web-push-public-key"
    }
    NTFY_WEB_PUSH_PRIVATE_KEY = {
      secret = "ntfy-op"
      key    = "web-push-private-key"
    }
    NTFY_WEB_PUSH_EMAIL_ADDRESS = {
      secret = "ntfy-op"
      key    = "web-push-email-address"
    }
  }
}

resource "kubernetes_manifest" "ntfy_op" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "ntfy-op"
      namespace = module.ntfy.namespace
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [ { extract = { key = "ntfy" } } ]
    }
  }
}
