resource "kubernetes_namespace" "metallb" {
  metadata {
    name = "metallb"
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
}

# Instead of using ServiceLB (k3s built-in), use MetalLB
# It gives the ability to ingress-nginx to have the correct client IP - and thus filter by VPN CIDRs
resource "helm_release" "metallb" {
  name      = "metallb"
  namespace = kubernetes_namespace.metallb.metadata.0.name
  atomic    = true

  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  # For upgrading: https://github.com/metallb/metallb/releases
  version = "0.14.8"

  values = [yamlencode({
    prometheus = {
      scrapeAnnotations = true
      # serviceMonitor    = { enabled = true }
    }
    speaker = { logLevel = "warn" }
  })]
}

resource "kubernetes_manifest" "metallb-ipaddresspool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "metallb-ipaddresspool"
      namespace = kubernetes_namespace.metallb.metadata.0.name
    }
    spec = {
      addresses = [
        # TODO: Pull these from the nodes
        "83.212.173.226/32",         # gr0
        "83.212.175.41/32",          # gr1
        "152.70.165.139/32",         # frankfurt0
        "130.162.36.16/32",          # frankfurt1
        "10.11.12.100-10.11.12.101", # VPN (upper CIDR)
        "10.11.12.200-10.11.12.201",
        "10.9.8.100-10.9.8.101", # VPN (lower CIDR)
        "10.9.8.200-10.9.8.201",
      ]
    }
  }
}

resource "kubernetes_manifest" "metallb-l2advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "metallb-l2advertisement"
      namespace = kubernetes_namespace.metallb.metadata.0.name
    }
  }

  depends_on = [kubernetes_manifest.metallb-ipaddresspool]
}
