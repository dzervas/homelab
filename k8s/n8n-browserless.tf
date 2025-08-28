moved {
  from = module.n8n-browserless
  to   = module.n8n_browserless
}

module "n8n_browserless" {
  source = "./docker-service"

  type  = "deployment"
  name  = "n8n-browserless"
  fqdn  = "browser.${var.domain}"
  auth  = "mtls"
  image = "ghcr.io/browserless/chromium"
  port  = 3000

  run_as_user = 999 # BLESS_USER_ID env var

  namespace        = module.n8n.namespace
  create_namespace = false
  node_selector    = { "provider" = "grnet" }

  ingress_enabled = true
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "3600"
    "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
    "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"

    # From https://docs.browserless.io/enterprise/nginx-docker#nginxconf
    "nginx.ingress.kubernetes.io/server-snippets" = <<EOF
      location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_cache_bypass $http_upgrade;
      }
    EOF
  }
  # ingress_annotations = {
  #   "nginx.ingress.kubernetes.io/server-snippet" = <<EOF
  #     location = /debugger {
  #       if ($is_args = "") {
  #         return 301 /debugger/?token=${random_password.n8n_browserless_token.result};
  #       }
  #     }
  #   EOF
  # }

  # liveness_http_path  = "/meta"
  # readiness_http_path = "/meta"

  env = {
    ALLOW_GET  = true # Required for some stuff in the n8n node
    PROXY_HOST = "n8n-browserless.${module.n8n.namespace}.svc.cluster.local"
    PROXY_PORT = "3000"
    PROXY_SSL  = false
    CONCURRENT = 5
    QUEUED     = 10
    TIMEOUT    = 15*60*1000
  }

  env_secrets = {
    TOKEN = {
      secret = kubernetes_manifest.n8n_browserless_token.manifest.metadata.name
      key    = "token"
    }
  }
}

resource "kubernetes_manifest" "n8n_browserless_token" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "n8n-browserless-token"
      namespace = "n8n"
    }
    spec = {
      refreshPolicy = "OnChange"
      target = {
        template = {
          data = {
            token = "{{ .password }}"
            credential_overwrite_data = jsonencode({
              browserlessApi = {
                url   = "http://n8n-browserless:3000",
                token = "{{ .password }}"
              }
            })
            global_vars = jsonencode({
              browserless_host     = "n8n-browserless"
              browserless_port     = "3000"
              browserless_token    = "{{ .password }}"
              browserless_endpoint = "ws://n8n-browserless:3000/?token={{ .password }}"
            })
          }
        }
      }
      dataFrom = [{
        sourceRef = {
          generatorRef = {
            apiVersion = "generators.external-secrets.io/v1alpha1"
            kind       = "ClusterGenerator"
            name       = "password"
          }
        }
      }]
    }
  }
}
