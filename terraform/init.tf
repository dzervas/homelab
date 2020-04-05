// TODO: Remove fixed addresses
terraform {
	backend "consul" {
      	// Set env var CONSUL_TOKEN
		address = "server.lan:8500"
		scheme = "http"
		path = "meta/tfstate"
	}
}

provider "consul" {
	address = "server.lan:8500"
	datacenter = "home"
}

provider "nomad" {
	address = "http://server.lan:4646"
	#region = "home"
}
