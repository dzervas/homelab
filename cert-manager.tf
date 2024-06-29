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

resource "kubernetes_manifest" "cm_cloudflare_api_token" {
  manifest = {
    apiVersion = "bitnami.com/v1alpha1"
    kind       = "SealedSecret"
    metadata = {
      name      = "cert-manager-cloudflare-api-token"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      encryptedData = {
        "api-token" = "AgCa3SSW7XfuSiTbuuuLW8DhfKh24a4lO7fPP+PK7K8qjLsN4t7hQanp3PIK1S9vRCxWOXyZnzymo3BgIw722yIKmNPif9vAeyRBZlErQg2ucKDWi4tv2/xlWoygLs6uMVOBbI8RQ8MBvfVpBbmdXBHrDRFZhHi9nGMPLzhPgf9wK8kP4orgn2u+dkkGhaXStSV+cGdoz1bKfAGrejdeNJ3pb6bC32VKtdYwxxWRqTc2hjnMjyv8mnhnxUUt8bAIXhvPU7BusYPlE8nZ7c90XUQ4C9ZfCUdEk6kco6sQka9oDYOL5QYaX60vf4N5t4ji5NeOmB9HvSq16reSgGP9pFG+qlgfXnddZ1N2tEV6U7urLX/eZdXuPcqsXL43Uc0R2matiYFFXFx8aMzIlBYeZSuzKjFf4UpOXQjlcKVF9EzZ99ikXYeYPL6mRtH6D+8bSjYTK6ROpECt5Gh3fwkAg6/N3+fvsvgoRKFJvnvQ5akcBOt3LFH+16r7uT0hf1/obfSXMYftzKrwNyjFq87rnWBpF3NaBnaiOBwTE+HqmA+WibNJIx+aPhCUwJUykN9a1I5v9+J1fgqGHz9P7Di2iB3HCMhsNnODGOOYAcVHpdIxRI2vRL8fkk1SsB4utPozQLDBm+apI9ANjm0Mb5FsArusedKyqlYOzIhaj/GUEvfjAUCxP98lmPfadwOD8IxfnGPPeMnkPWP9MHVKTNwxFzawWFKwJzhLEEKrGBue+nJoBVNFeX5b8y/a"
      }
      template = {
        metadata = {
          name      = "cert-manager-cloudflare-api-token"
          namespace = helm_release.cert_manager.namespace
        }
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
