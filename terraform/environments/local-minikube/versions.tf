terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Local state storage for Minikube
  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)
}

provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = var.kube_context
  }
}
