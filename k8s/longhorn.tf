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
  version    = "1.8.1"
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
        "nginx.ingress.kubernetes.io/auth-tls-secret"        = "${kubernetes_namespace.longhorn-system.metadata.0.name}/client-ca"
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

    global = {
      tolerations = [{
        key      = "longhorn"
        operator = "Equal"
        value    = "true"
        effect   = "NoSchedule"
      }]
    }

    networkPolicies = {
      enabled = true
    }
  })]

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_manifest" "longhorn_s3" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "longhorn-s3"
      namespace = kubernetes_namespace.longhorn-system.metadata.0.name
    }
    spec = {
      refreshInterval = "10m"
      secretStoreRef = {
        name = "1password"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "longhorn-s3"
        creationPolicy = "Owner"
        template = {
          data = {
            AWS_ENDPOINTS         = "http://rclone.rclone.svc.cluster.local"
            AWS_ACCESS_KEY_ID     = "{{ .access }}"
            AWS_SECRET_ACCESS_KEY = "{{ .secret }}"
          }
        }
      }
      data = [
        {
          secretKey = "access"
          remoteRef = {
            key      = "rclone-s3"
            property = "access-id"
          }
        },
        {
          secretKey = "secret"
          remoteRef = {
            key      = "rclone-s3"
            property = "secret-key"
          }
        }
      ]
    }
  }
}
