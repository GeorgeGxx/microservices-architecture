variable "name" {
  type        = string
  description = "Base resource name prefix"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the NLB will be deployed"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs for the NLB"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}
