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
  # platform-multicloud.ps1 (-Provider aws) and GitHub Actions must use this same bucket/table pair.
  # Terraform >= 1.10 supports native S3 object lockfiles (use_lockfile = true).
  backend "s3" {
    bucket         = "georgegxx-msa-tfstate-prod"
    key            = "aws/microservices.tfstate"
    region         = "us-east-1"
    dynamodb_table = "georgegxx-msa-tflock-prod"
    use_lockfile   = true
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
