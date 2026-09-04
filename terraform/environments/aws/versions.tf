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

  # State is per-workspace: key includes ${terraform.workspace}
  # bootstrap the bucket/table once with scripts/terraform-bootstrap-backend.sh
  backend "s3" {
    bucket         = "georgegxx-ecommerce-tfstate"
    key            = "aws/ecommerce.tfstate"
    region         = "us-east-1"
    dynamodb_table = "georgegxx-ecommerce-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ecommerce"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}
