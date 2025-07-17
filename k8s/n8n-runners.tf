module "n8n_runners" {
  source = "./docker-service"

  namespace        = module.n8n.namespace
  create_namespace = false
  ingress_enabled  = false

  type     = "deployment"
  replicas = 0

  name    = "n8n-runners"
  image   = "ghcr.io/dzervas/n8n:latest"
  command = ["/usr/local/bin/task-runner-launcher"]
  args    = ["javascript"]

  # TODO: Liveness probe GET /healthz on 5680

  env = {
    TZ               = var.timezone
    GENERIC_TIMEZONE = var.timezone

    N8N_RUNNERS_TASK_BROKER_URI       = "http://n8n:5679"
    N8N_RUNNERS_MAX_CONCURRENCY       = 5
    N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT = 60 # 1 minute

    # TODO: Add mem limits
    # NODE_OPTIONS = "--max-old-space-size=<limit>"
  }

  env_secrets = {
    N8N_RUNNERS_AUTH_TOKEN = {
      secret = kubernetes_manifest.n8n_runner_token.manifest.metadata.name
      key    = "password"
    }
  }
}

resource "kubernetes_manifest" "n8n_runner_token" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "n8n-runner-token"
      namespace = "n8n"
    }
    spec = {
      refreshPolicy = "OnChange"
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
