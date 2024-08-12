terraform {
  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-k8s"
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.14"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "gr"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "gr"
  }
}

provider "random" {}

provider "onepassword" {}
