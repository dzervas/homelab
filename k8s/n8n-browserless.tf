module "n8n-browserless" {
  source = "./docker-service"

  type             = "deployment"
  name             = "n8n-browserless"
  namespace        = module.n8n.namespace
  create_namespace = false
  fqdn             = "browser.${var.domain}"
  ingress_enabled  = true
  # ingress_annotations = {
  #   "nginx.ingress.kubernetes.io/server-snippet" = <<EOF
  #     location = /debugger {
  #       if ($is_args = "") {
  #         return 301 /debugger/?token=${random_password.n8n_browserless_token.result};
  #       }
  #     }
  #   EOF
  # }
  auth          = "mtls"
  image         = "ghcr.io/browserless/chromium"
  port          = 3000
  node_selector = { "kubernetes.io/arch" = "amd64" }
  env = {
    ALLOW_GET  = true # Required for some stuff in the n8n node
    PROXY_HOST = "n8n-browserless.${module.n8n.namespace}.svc.cluster.local"
    PROXY_PORT = "3000"
    PROXY_SSL  = false
    CONCURRENT = 5
    QUEUED     = 10
  }

  env_secrets = {
    TOKEN = {
      secret = kubernetes_manifest.n8n_browserless_token.manifest.metadata.name
      key   = "token"
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
