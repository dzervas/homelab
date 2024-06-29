output "namespace" {
  value = kubernetes_namespace.docker.metadata.0.name
}
