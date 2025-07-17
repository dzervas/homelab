locals {
  cert_duration = "87658h0m0s" # 10 years
  domains = [
    var.domain,
    "staging.blogaki.io",
    "staging.dzerv.it",
    "*.${var.domain}",
    "*.staging.blogaki.io",
  ]

  guests = {
    psof = [module.n8n.fqdn]
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
        organizations = [var.domain]
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
      duration   = kubernetes_manifest.cm_client_ca.object.spec.duration
      privateKey = {
        algorithm = kubernetes_manifest.cm_client_ca.object.spec.privateKey.algorithm
        size      = kubernetes_manifest.cm_client_ca.object.spec.privateKey.size
      }
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

resource "kubernetes_manifest" "guests_certificates" {
  for_each = local.guests

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "client-guest-${each.key}"
      namespace = helm_release.cert_manager.namespace
      labels = {
        managed_by = "terraform"
      }
    }
    spec = {
      secretName = "client-guest-${each.key}-certificate"
      dnsNames   = each.value
      duration   = kubernetes_manifest.cm_client_ca.object.spec.duration
      privateKey = {
        algorithm = kubernetes_manifest.cm_client_ca.object.spec.privateKey.algorithm
        size      = kubernetes_manifest.cm_client_ca.object.spec.privateKey.size
      }
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

# Distribute the client ca to all namespaces so that ingress-nginx has access to it
data "kubernetes_secret" "cm_client_ca" {
  metadata {
    name      = "client-ca-certificate"
    namespace = helm_release.cert_manager.namespace
  }
}

resource "kubernetes_secret_v1" "client_ca_everywhere" {
  for_each = { for ns in data.kubernetes_all_namespaces.all.namespaces : ns => ns if !contains(["kube-system", "ingress", "cert-manager"], ns) }
  metadata {
    name      = "client-ca"
    namespace = each.value
  }
  data = {
    "ca.crt" = data.kubernetes_secret.cm_client_ca.data["ca.crt"]
  }
}
