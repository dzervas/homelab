locals {
  op_secrets = { for section in data.onepassword_item.homelab.section :
    section.label => {
      for field in section.field : field.label => field.value
    }
  }
}

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

data "onepassword_item" "homelab" {
  vault = var.op_vault
  title = "homelab-k8s"
}
