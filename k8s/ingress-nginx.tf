resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = "ingress"
    labels = {
      # Required due to hostPort
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      managed_by                                   = "terraform"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = kubernetes_namespace_v1.ingress.metadata[0].name
  create_namespace = false
  atomic           = true
  timeout          = 600 # Daemonset takes time

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # For upgrading: https://github.com/kubernetes/ingress-nginx/releases
  version = "4.12.4"

  values = [yamlencode({
    controller = {
      # TODO: Eliminate this
      allowSnippetAnnotations     = true
      enableAnnotationValidations = true

      watchIngressWithoutClass = true
      ingressClassResource     = { default = true }

      networkPolicy = { enabled = true }

      kind     = "DaemonSet"
      hostPort = { enabled = true }
      # No LB, so no use ClusterIP with host network
      service = { type = "ClusterIP" }

      # hostNetwork = true
      # dnsPolicy   = "ClusterFirstWithHostNet" # Use cluster DNS, even in host network

      config = { custom-http-errors = "503" }

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled = true
        }
      }
    }

    defaultBackend = {
      enabled = true
      image = {
        registry = "registry.k8s.io"
        image = "ingress-nginx/custom-error-pages"
        tag = "v1.2.3"
      }
      extraVolumes = [{
        name = "custom-error-pages"
        configMap = {
          name = "custom-error-pages"
          items = [
            { key = "503", path = "503.html" },
          ]
        }
      }]
      extraVolumeMounts = [{
        name = "custom-error-pages"
        mountPath = "/www"
      }]
    }
  })]
}

resource "kubernetes_config_map_v1" "ingress_custom_error_pages" {
  metadata {
    name = "custom-error-pages"
    namespace = kubernetes_namespace_v1.ingress.metadata[0].name
  }

  data = {
    "503" = file("./503.html")
  }
}
