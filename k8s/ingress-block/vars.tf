variable "fqdn" {
  type        = string
  description = "Domain for the ingress block"
}

variable "additional_annotations" {
  type        = map(string)
  description = "Additional annotations for the ingress block"
  default     = {}
}

variable "mtls_enabled" {
  type        = bool
  description = "Enable mTLS authentication for the ingress block"
  default     = true
}

variable "namespace" {
  type = string
}
