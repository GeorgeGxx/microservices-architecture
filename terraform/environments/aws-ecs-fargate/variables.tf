variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier prefix"
  type        = string
  default     = "microservices"
}

variable "environment" {
  description = "Target environment stage (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "container_registry" {
  description = "Docker image registry (ECR or Docker Hub)"
  type        = string
  default     = "ghcr.io/georgegxx"
}

variable "log_retention_days" {
  description = "Specifies the number of days to retain CloudWatch log events (e.g., 30, 90, 365)"
  type        = number
  default     = 30
}

