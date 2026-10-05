terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Shared provider backend with isolated dev/staging/prod workspaces.
  # platform.ps1 and GitHub Actions must use this same bucket/table pair.
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
