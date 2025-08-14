locals {
  op_secrets = { for section in data.onepassword_item.homelab.section :
    section.label => {
      for field in section.field : field.label => field.value
    }
  }
}

terraform {
  required_version = ">= 1.12.0"

  backend "kubernetes" {
    secret_suffix  = "homelab-k8s"
    namespace      = "kube-system"
    config_path    = "~/.kube/config"
    config_context = "gr"
  }

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2"
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
