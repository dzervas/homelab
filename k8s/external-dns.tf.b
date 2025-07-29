resource "helm_release" "external_dns" {
  name             = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  atomic           = true

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  # For upgrading: https://github.com/kubernetes-sigs/external-dns/releases
  version = "1.18.0"

  # Can't make it use a CNAME to target the nodes. The ingress resource need to have a status
  # that points to the hostname, instead of the clusterip that is currently the case

  values = [yamlencode({
    sources  = ["ingress"]
    policy   = "sync" # Add, update & delete records
    registry = "txt"

    # For cloudflare proxied records add annotation to ingress:
    # external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"
    provider           = { name = "cloudflare" }
    managedRecordTypes = ["CNAME"]
    domainFilters      = [var.domain]

    env = [{
      name = "CF_API_TOKEN"
      valueFrom = {
        secretKeyRef = {
          name = "cloudflare-api-token"
          key  = "cloudflare-api-token"
        }
      }
    }]

    extraArgs = [
      "--ingress-class=nginx",
      "--cloudflare-record-comment=\"managed by external-dns\"",
      "--no-resolve-service-load-balancer-hostname", # Do not resolve the nodes' address
    ]

    rbac = {
      additionalPermissions = [{
        apiGroups = [""]
        resources = ["nodes"]
        verbs     = ["list"]
      }]
    }

    serviceMonitor = { enabled = true }
  })]
}

resource "kubernetes_manifest" "external_dns_cf" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "cloudflare-api-token"
      namespace = helm_release.external_dns.namespace
    }
    spec = {
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      dataFrom = [{ extract = { key = "cert-manager" } }]
    }
  }
}
