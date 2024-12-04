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
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
    random = {
      source = "hashicorp/random"
    }
    toml = {
      source = "Tobotimus/toml"
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

provider "toml" {}

data "onepassword_item" "homelab" {
  vault = var.op_vault
  title = "homelab-k8s"
}
