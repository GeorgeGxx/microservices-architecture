terraform {
  required_version = ">= 1.8.0"

  # Partial backend configuration is supplied from the operator's ignored
  # terraform/backend-config/gcp.hcl file. GCS provides state locking.
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
