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

  env = {
    NTFY_BASE_URL = "https://notify.${var.domain}"
    NTFY_BEHIND_PROXY = "true"
    NTFY_CACHE_DURATION = "96h" # keep undelivered notifications for 4 days
    NTFY_LISTEN_HTTP = ":8080"
  }
}
