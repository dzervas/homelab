variable "cf_zone_id" {
  # Insert your Cloudflare zone ID here
}

variable "service_name" {
  # Insert the name of your Kubernetes service here
}

variable "service_port" {
  # Insert the port number of your Kubernetes service here
}

variable "cf_lb_name" {
  # Insert the name you want to give the Cloudflare load balancer here
}

resource "cloudflare_load_balancer" "lb" {
  name = var.cf_lb_name

  monitor {
    type = "http"
    interval = 10
    retries = 3
    timeout = 5
    method = "GET"
    port = var.service_port
    path = "/"
    header {
      name = "Host"
      value = var.service_name
    }
  }

  pool {
    name = "pool1"
    origin {
      name = var.service_name
      address = cloudflare_load_balancer_pool.origin_ip_addresses(var.service_name)[0]
      port = var.service_port
      weight = 1
    }
  }

  dns {
    type = "CNAME"
    name = var.service_name
    value = cloudflare_load_balancer.lb_hostname
    proxied = true
  }
}

resource "cloudflare_load_balancer_pool" "pool" {
  lb_id = cloudflare_load_balancer.lb.id
  name = "pool1"
}

data "kubernetes_service" "my-service" {
  metadata {
    name = var.service_name
  }
}

output "cloudflare_dns" {
  value = cloudflare_load_balancer.lb.hostname
}
