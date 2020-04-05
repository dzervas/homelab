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
