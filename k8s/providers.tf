locals {
  op_secrets = { for section in data.onepassword_item.homelab.section :
    section.label => {
      for field in section.field : field.label => field.value
    }
  }
}

terraform {
  required_version = ">= 1.12.0"

  cloud {
    organization = "dzervas"

    workspaces {
      name = "homelab-k8s"
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "gr"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "gr"
  }
}

provider "onepassword" {}

data "onepassword_item" "homelab" {
  vault = var.op_vault
  title = "homelab-k8s"
}
