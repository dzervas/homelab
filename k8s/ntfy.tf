module "ntfy" {
  source = "./docker-service"

  type              = "deployment"
  name              = "ntfy"
  image             = "binwiederhier/ntfy"
  args              = ["serve"]
  image_pull_policy = true
  port              = 8080

  fqdn = "notify.${var.domain}"
  auth = "mtls"

  pvs = {
    "/var/cache/ntfy" = {
      name = "cache"
      size = "20Gi"
    }
    "/var/lib/ntfy" = {
      name = "db"
      size = "128Mi"
    }
  }

  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size"    = "10g"
    "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
    "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    "nginx.ingress.kubernetes.io/server-snippets"    = <<EOF
      location / {
        proxy_set_header Upgrade $http_upgrade;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Host $host;
        proxy_set_header Connection "upgrade";
        proxy_cache_bypass $http_upgrade;
      }
    EOF

  }

  env = {
    NTFY_AUTH_FILE      = "/var/lib/ntfy/user.db"
    NTFY_BASE_URL       = "https://notify.${var.domain}"
    NTFY_BEHIND_PROXY   = "true"
    NTFY_CACHE_DURATION = "96h" # keep undelivered notifications for 4 days
    NTFY_LISTEN_HTTP    = ":8080"
    NTFY_WEB_PUSH_FILE  = "/var/cache/ntfy/webpush.db"

    NTFY_ATTACHMENT_CACHE_DIR        = "/var/cache/ntfy/attachments"
    NTFY_ATTACHMENT_TOTAL_SIZE_LIMIT = "20G"
    NTFY_ATTACHMENT_FILE_SIZE_LIMIT  = "10G"
    NTFY_ATTACHMENT_EXPIRY_DURATION  = "24h"
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
      dataFrom = [{ extract = { key = "ntfy" } }]
    }
  }
}
