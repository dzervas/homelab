// TODO: Remove fixed addresses
terraform {
  backend "consul" {
    // Set env var CONSUL_HTTP_TOKEN
    address = "127.0.0.1:8500"
    scheme = "http"
    path = "meta/tfstate"
  }
}

provider "consul" {
  // Set env var CONSUL_HTTP_TOKEN
  address = "127.0.0.1:8500"
  datacenter = "home"
}

provider "nomad" {
  // Set env var NOMAD_TOKEN
  address = "http://127.0.0.1:4646"
  #region = "home"
}

provider "vault" {
  // Set env var VAULT_TOKEN
  address = "http://127.0.0.1:8200"
}
