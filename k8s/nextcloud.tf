locals {
  uid = 33 # www-data for apache is 33 and 82 for nginx
  security_context = {
    runAsUser                = local.uid
    runAsGroup               = local.uid
    runAsNonRoot             = true
    fsGroup                  = local.uid
    allowPrivilegeEscalation = false
    seccompProfile = {
      type = "RuntimeDefault"
    }
  }
}

module "nextcloud_ingress" {
  source = "./ingress-block"

  namespace = "nextcloud"
  fqdn      = "files.${var.domain}"
  # mtls_enabled = true
  additional_annotations = {
    "cert-manager.io/cluster-issuer"                  = "letsencrypt"
    "magicentry.rs/name"                              = "NextCloud"
    "magicentry.rs/realms"                            = "files,public"
    "magicentry.rs/auth-url"                          = "true"
    "magicentry.rs/manage-ingress-nginx"              = "true"
    "nginx.ingress.kubernetes.io/ssl-redirect"        = "true"
    "nginx.ingress.kubernetes.io/proxy-body-size"     = "10g"
    "nginx.ingress.kubernetes.io/auth-url"            = "http://magicentry.auth.svc.cluster.local:8080/auth-url/status"
    "nginx.ingress.kubernetes.io/auth-signin"         = "https://auth.dzerv.art/login"
    "nginx.ingress.kubernetes.io/auth-cache-duration" = "200 202 10m, 401 1m"
    "nginx.ingress.kubernetes.io/auth-cache-key"      = "$remote_user$http_authorization"

  }
}

resource "helm_release" "nextcloud" {
  name             = "nextcloud"
  namespace        = "nextcloud"
  create_namespace = true
  atomic           = true

  repository = "https://nextcloud.github.io/helm/"
  chart      = "nextcloud"
  values = [yamlencode({
    ingress = module.nextcloud_ingress.host_obj
    podLabels = {
      "magicentry.rs/enable" = "true"
      "rclone/enable"        = "true"
    }

    nextcloud = {
      host = module.nextcloud_ingress.fqdn

      configs = {
        // Insists on rolling the permissions back to 777, so don't check
        "noperms.config.php" = <<EOF
          <?php
            $CONFIG = array(
              "check_data_directory_permissions" => false, # https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/
              "log_type" => "file", # Defaults to `/var/www/html/data/nextcloud.log`
              "loglevel" => 2, # 0 = debug, 1 = info, 2 = warning, 3 = error, 4 = fatal
            );
        EOF
      }

      existingSecret = {
        enabled         = true
        secretName      = "nextcloud-secrets-op"
        usernameKey     = "username"
        passwordKey     = "password"
        smtpUsernameKey = "smtp-username"
        smtpPasswordKey = "smtp-password"
        smtpHostKey     = "smtp-host"
      }

      mail = {
        enabled     = true
        fromAddress = "DZervArt Files <files@dzerv.art>"
        domain      = "dzerv.art"
        smtp = {
          secure   = "ssl"
          port     = 587
          authtype = "login"
        }
      }

      objectStore = {
        s3 = {
          enabled      = true
          ssl          = false
          usePathStyle = true
          autoCreate   = true
          prefix       = ""

          host = "rclone.rclone.svc.cluster.local"
          port = 80

          existingSecret = "rclone-s3-op"
          secretKeys = {
            host      = "host"
            accessKey = "access-id"
            secretKey = "secret-key"
            bucket    = "files-bucket"
          }
        }
      }

      defaultConfigs = {
        "imaginary.config.php" = true
      }

      podSecurityContext = local.security_context
    }

    persistence = {
      enabled = true
      nextcloudData = {
        enabled = true
      }
    }

    cronJob = {
      enabled         = true
      securityContext = local.security_context
    }

    imaginary = {
      enabled            = true
      podSecurityContext = local.security_context
    }

    # metrics = {
    #   enabled            = true
    #   podSecurityContext = local.security_context
    # }
  })]

  depends_on = [
    kubernetes_manifest.nextcloud_secrets,
    kubernetes_manifest.nextcloud_s3,
  ]
}

resource "kubernetes_manifest" "nextcloud_secrets" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "nextcloud-secrets-op"
      namespace = "nextcloud"
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/nextcloud"
    }
  }
}

resource "kubernetes_manifest" "nextcloud_s3" {
  manifest = {
    apiVersion = "onepassword.com/v1"
    kind       = "OnePasswordItem"
    metadata = {
      name      = "rclone-s3-op"
      namespace = "nextcloud"
    }
    spec = {
      itemPath = "vaults/k8s-secrets/items/rclone-s3"
    }
  }
}

# resource "kubernetes_persistent_volume_claim_v1" "nextcloud" {
#   metadata {
#     name      = "nextcloud-data"
#     namespace = "nextcloud"
#     labels = {
#       managed_by = "terraform"
#       service    = "nextcloud"
#     }
#   }

#   spec {
#     access_modes = ["ReadWriteOnce"]
#     resources {
#       requests = {
#         storage = "10Gi"
#       }
#     }
#   }
# }
