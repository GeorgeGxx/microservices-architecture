terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # AWS Well-Architected Security Pillar & Principle of Least Privilege (PoLP):
  # Remote state is isolated per environment (staging vs prod).
  # Run scripts/cloud/terraform/terraform-bootstrap-backend.ps1 to provision the backends.
  # Dynamic backend configuration can be supplied during `terraform init`:
  #   terraform init -backend-config="bucket=georgegxx-msa-tfstate-${ENV}" -backend-config="dynamodb_table=georgegxx-msa-tflock-${ENV}"
  backend "s3" {
    bucket         = "georgegxx-msa-tfstate-prod"
    key            = "aws/microservices.tfstate"
    region         = "us-east-1"
    dynamodb_table = "georgegxx-msa-tflock-prod"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "microservices-architecture"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
      Compliance  = "AWS-Well-Architected-Security-Pillar"
    }
  }
}
