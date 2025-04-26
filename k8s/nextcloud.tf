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

  namespace    = "nextcloud"
  fqdn         = "files.${var.domain}"
  mtls_enabled = true
  additional_annotations = {
    "cert-manager.io/cluster-issuer"              = "letsencrypt"
    "nginx.ingress.kubernetes.io/ssl-redirect"    = "true"
    "nginx.ingress.kubernetes.io/proxy-body-size" = "10g"
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
      "rclone/enable" = "true"
    }
    phpClientHttpsFix = {
      enabled = true
    }

    nextcloud = {
      host = module.nextcloud_ingress.fqdn

      configs = {
        // Insists on rolling the permissions back to 777, so don't check
        "noperms.config.php" = <<EOF
          <?php
            $CONFIG = array(
              "check_data_directory_permissions" => false, # https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/
              "trusted_proxies" => ["10.43.0.0/16"],
              "trusted_domains" => ["${module.nextcloud_ingress.fqdn}"],
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

      podSecurityContext = local.security_context
    }

    persistence = {
      enabled = true
      nextcloudData = {
        enabled = true
      }
    }

    cronjob = {
      enabled         = true
      securityContext = local.security_context
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
