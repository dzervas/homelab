terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-k8s"
    }
  }

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "gr"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    config_context = "gr"
  }
}
