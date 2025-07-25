resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  atomic           = true

  repository = "https://charts.jetstack.io/"
  chart      = "cert-manager"
  # For upgrading: https://cert-manager.io/docs/releases/upgrading/upgrading-1.12-1.13
  # https://github.com/cert-manager/cert-manager/releases/latest
  version = "v1.17.1"

  values = [yamlencode({
    crds = { enabled = true }
    prometheus = {
      servicemonitor = { enabled = true }
    }
    webhook = {
      networkPolicy = {
        enabled = true
      }
    }
  })]
}

# Default, self-signed issuer
resource "kubernetes_manifest" "cm_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned"
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      selfSigned = {}
    }
  }
}

# Normal, dzerv.art issuer
resource "kubernetes_manifest" "cm_letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt"
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      acme = {
        email  = "dzervas+homelab@dzervas.gr"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "cert-manager-cluster-issuer-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                email = "dzervas@dzervas.gr"
                apiTokenSecretRef = {
                  name = kubernetes_manifest.cm_op_secrets.manifest.metadata.name
                  key  = "cloudflare-api-token"
                }
              }
              selector = {
                dnsNames = [
                  var.domain,
                  "*.${var.domain}"
                ]
              }
            }
          },
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "cm_op_secrets" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "cert-manager-op"
      namespace = helm_release.cert_manager.namespace
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

resource "kubernetes_manifest" "cm_headscale_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "headscale-vpn"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }

    spec = {
      secretName = "headscale-vpn-certificate"
      dnsNames   = ["vpn.${var.domain}"]
      issuerRef = {
        name = "letsencrypt"
        kind = "ClusterIssuer"
      }
    }
  }
}
