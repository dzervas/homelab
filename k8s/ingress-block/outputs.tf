locals {
  partial = {
    enabled = true
    tls = [
      {
        hosts      = [var.fqdn]
        secretName = "${replace(var.fqdn, ".", "-")}-cert"
      }
    ]
    annotations = merge(
      {
        "cert-manager.io/cluster-issuer"           = "letsencrypt"
        "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
      },
      var.mtls_enabled ? {
        "nginx.ingress.kubernetes.io/auth-tls-verify-client" = "on"
        "nginx.ingress.kubernetes.io/auth-tls-secret"        = "${var.namespace}/client-ca"
        "nginx.ingress.kubernetes.io/auth-tls-verify-depth"  = "1"
      } : {},
    var.additional_annotations)
  }
}

output "host_list" {
  value = merge(local.partial, {
    ingressClassName = "nginx"
    path             = "/"
    pathType         = "Prefix"
    hosts            = [var.fqdn]
  })
}

output "host_obj" {
  value = merge(local.partial, {
    enabled   = true
    className = "nginx"
    hosts = [{
      host = var.fqdn
      paths = [{
        path     = "/"
        pathType = "Prefix"
      }]
    }]
  })
}
