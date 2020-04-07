variable "email" {
  description = "E-Mail address (mainly for Let's Encrypt)"
  type = string
}

variable "tz" {
  description = "Local timezone of the server"
  type = string
}

variable "domain" {
  description = "Domain name used for the services"
  type = string
}

variable "pgp_key" {
  description = "PGP key to encrypt secrets with - can be keybase:<username>"
  type = string
}

variable "consul_address" {
  description = "Consul HTTP API address (ex. 127.0.0.1:8500)"
  type = string
}
