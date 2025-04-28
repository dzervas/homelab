variable "namespace" {
  type        = string
  description = "The namespace to deploy the service in"
}

variable "password_secret_name" {
  type        = string
  description = "The name of the secret containing the database password"
}

variable "password_secret_key" {
  type        = string
  description = "The key in the secret containing the database password"
  default     = "postgres-password"
}

variable "timezone" {
  type        = string
  description = "The timezone to set in the container"
  default     = "Europe/Athens"
}
