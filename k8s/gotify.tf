module "gotify" {
  source = "./docker-service"

  type  = "statefulset"
  name  = "gotify"
  image = "ghcr.io/gotify/server"
  port  = 8080

  fqdn = "notify.${var.domain}"
  auth = "mtls"

  pvs = {
    "/app/data" = {
      name = "data"
      size = "20Gi"
    }
  }

  liveness_http_path  = "/health"
  readiness_http_path = "/health"

  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size"       = "10g"
    "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "1m"
    "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "1m"
    "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "1m"
    # https://gotify.net/docs/nginx
    "nginx.ingress.kubernetes.io/server-snippets"       = <<EOF
      location / {
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto http;

        proxy_set_header Host $http_host;
      }
    EOF

  }

  env = {
    TZ = var.timezone

    GOTIFY_SERVER_PORT                  = "8080"
    GOTIFY_SERVER_TRUSTEDPROXIES        = "[10.42.0.0/16]"
    GOTIFY_SERVER_STREAM_ALLOWEDORIGINS = replace("[notify.${var.domain}]", ".", "\\.")

    GOTIFY_DEFAULTUSER_NAME = "dzervas"
  }

  env_secrets = {
    GOTIFY_DEFAULTUSER_NAME = {
      secret = "gotify-op"
      key    = "username"
    }
    GOTIFY_DEFAULTUSER_PASS = {
      secret = "gotify-op"
      key    = "password"
    }
  }
}

resource "kubernetes_manifest" "gotify_op" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "gotify-op"
      namespace = module.gotify.namespace
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [{ extract = { key = "gotify" } }]
    }
  }
}
