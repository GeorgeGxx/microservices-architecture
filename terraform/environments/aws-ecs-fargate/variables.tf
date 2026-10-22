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
  description = "Docker Hub namespace used for application images"
  type        = string
  default     = "docker.io/georgegxx"
}

variable "cosmo_router_image_tag" {
  description = "40-character Git commit SHA tag of the published Docker Hub Cosmo Router image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.cosmo_router_image_tag))
    error_message = "cosmo_router_image_tag must be the 40-character lowercase Git SHA published to Docker Hub."
  }
}

variable "frontend_image_tag" {
  description = "40-character Git commit SHA tag of the published Docker Hub frontend image"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.frontend_image_tag))
    error_message = "frontend_image_tag must be the 40-character lowercase Git SHA published to Docker Hub."
  }
}

variable "log_retention_days" {
  description = "Specifies the number of days to retain CloudWatch log events (e.g., 30, 90, 365)"
  type        = number
  default     = 30
}

