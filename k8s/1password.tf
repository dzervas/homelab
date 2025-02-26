resource "kubernetes_namespace_v1" "_1password" {
  metadata {
    name = "1password"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
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
# kubectl create secret generic connect-credentials -n 1password --from-literal=token=(op read op://secrets/operator-token/credential) --from-literal=1password-credentials.json=(op read op://secrets/operator-credentials/1password-credentials.json) --dry-run=client -o yaml

resource "helm_release" "_1password" {
  name       = "1password"
  namespace  = kubernetes_namespace_v1._1password.metadata.0.name
  repository = "https://1password.github.io/connect-helm-charts/"
  chart      = "connect"
  # For updates: https://github.com/1Password/connect-helm-charts/releases
  version = "1.17.0"
  values = [yamlencode({
    connect = {
      credentialsName = "connect-credentials"
    }
    operator = {
      create = true
      token = {
        name = "connect-credentials"
      }
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}
