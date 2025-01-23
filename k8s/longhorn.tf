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
      managed_by                                   = "terraform"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = kubernetes_namespace.longhorn-system.metadata.0.name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.8.0"
  timeout    = 1800 # Fucking gr1
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

    defaultSettings = {
      backupTarget                      = "s3://longhorn@us-east-1/backups"
      backupTargetCredentialSecret      = "longhorn-s3"
      orphanAutoDeletion                = true
      replicaAutoBalance                = "best-effort"
      storageMinimalAvailablePercentage = 10
    }

    csi = {
      # See https://github.com/longhorn/longhorn/issues/1861
      kubeletRootDir = "/var/lib/kubelet/"
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_secret_v1" "longhorn_s3" {
  metadata {
    name      = "longhorn-s3"
    namespace = kubernetes_namespace.longhorn-system.metadata.0.name
  }
  data = {
    AWS_ENDPOINTS         = "http://rclone.rclone.svc.cluster.local"
    AWS_ACCESS_KEY_ID     = random_password.rclone_access_key.result
    AWS_SECRET_ACCESS_KEY = random_password.rclone_secret_key.result
  }
}
