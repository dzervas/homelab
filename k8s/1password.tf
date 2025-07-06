resource "kubernetes_namespace_v1" "_1password" {
  metadata {
    name = "1password"
    labels = {
      # "pod-security.kubernetes.io/enforce"         = "restricted"
      # "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Requires Connect credentials:
# 1password.com > developer tools > Infrastructure Secrets Management > Other > Create a Connect server
# Save the token and the 1password-credentials.json file to `operator-token` and `operator-credentials` in 1password (from the webui)
# kubectl create secret generic connect-credentials -n 1password --from-literal=1password-credentials.json=(op read op://secrets/operator-credentials/1password-credentials.json | base64 -w 0) --dry-run=client -o yaml
# kubectl create secret generic connect-token -n 1password --from-literal=token=(op read op://secrets/operator-token/credential) --dry-run=client -o yaml

resource "helm_release" "_1password" {
  name             = "1password"
  namespace        = kubernetes_namespace_v1._1password.metadata[0].name
  create_namespace = false
  repository       = "https://1password.github.io/connect-helm-charts/"
  chart            = "connect"
  # For updates: https://github.com/1Password/connect-helm-charts/releases
  version = "1.17.1"
  values = [yamlencode({
    connect = {
      credentialsName = "connect-credentials"
      serviceType     = "ClusterIP"
      api = {
        serviceMonitor = {
          enabled = true
        }
      }
    }
    operator = {
      create = true
      token = {
        name = "connect-token"
      }

      # https://github.com/1Password/connect-helm-charts/issues/231
      # customEnvVars = [{
      #   name = "OP_CONNECT_TOKEN"
      #   valueFrom = {
      #     secretKeyRef = {
      #       name = "connect-token"
      #       key = "token"
      #     }
      #   }
      # }]
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}
