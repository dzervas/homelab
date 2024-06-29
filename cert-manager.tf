locals {
  main_domain = "dzerv.art"
  domains = [
    "dzerv.art",
    "staging.blogaki.io",
    "staging.dzerv.it",
    "*.dzerv.art",
    "*.staging.blogaki.io",
  ]
  cert_duration = "87658h0m0s" # 10 years
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  atomic           = true

  repository = "https://charts.jetstack.io/"
  chart      = "cert-manager"
  version    = "v1.12.12"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_manifest" "cm_certificates" {
  for_each = toset(["desktop", "laptop", "mobile", "tablet"])

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "client-${each.key}"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      secretName = "client-${each.key}-certificate"
      dnsNames   = kubernetes_manifest.cm_client_ca.object.spec.dnsNames
      # isCA       = false
      duration   = kubernetes_manifest.cm_client_ca.object.spec.duration
      privateKey = kubernetes_manifest.cm_client_ca.object.spec.privateKey
      usages = [
        "server auth",
        "client auth",
      ]

      issuerRef = {
        name = kubernetes_manifest.cm_client_ca.object.metadata.name
        kind = "Issuer"
      }
    }

  }
}

# Issuer
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

resource "kubernetes_manifest" "cm_client_ca" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "client-ca"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      secretName = "client-ca-certificate"
      dnsNames   = local.domains
      subject = {
        organizations = [local.main_domain]
      }
      duration = local.cert_duration
      privateKey = {
        algorithm = "ECDSA"
        size      = 384
      }
      isCA = true

      issuerRef = {
        name = kubernetes_manifest.cm_cluster_issuer.object.metadata.name
        kind = "ClusterIssuer"
      }
    }
  }
}

resource "kubernetes_manifest" "cm_client_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "client-ca"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      ca = {
        secretName = kubernetes_manifest.cm_client_ca.object.spec.secretName
      }
    }
  }
}

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
                  name = "cert-manager-cloudflare-api-token"
                  key  = "api-token"
                }
              }
              selector = {
                dnsNames = [
                  local.main_domain,
                  "*.${local.main_domain}"
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
