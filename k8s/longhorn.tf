resource "kubernetes_namespace" "longhorn-system" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "privileged"
      "pod-security.kubernetes.io/audit-version"   = "latest"
      "pod-security.kubernetes.io/warn"            = "privileged"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    }
  }
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = kubernetes_namespace.longhorn-system.metadata.0.name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.6.2"
  values = [yamlencode({
    persistence = {
      defaultClass             = true
      defaultDataLocality      = "best-effort"
      defaultClassReplicaCount = 2
    }
    ingress = {
      enabled          = true
      ingressClassName = "nginx"
      annotations = {
        "cert-manager.io/cluster-issuer"                     = "letsencrypt"
        "nginx.ingress.kubernetes.io/ssl-redirect"           = true
        "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
        "nginx.ingress.kubernetes.io/auth-tls-secret"        = "cert-manager/client-ca-certificate"
        "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = 1
      }
      host      = "storage.${var.domain}"
      tls       = true
      tlsSecret = "storage-${replace(var.domain, ".", "-")}-cert"
    }
  })]
}
