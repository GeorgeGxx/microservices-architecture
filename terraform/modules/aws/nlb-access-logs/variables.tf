variable "name" {
  type        = string
  description = "Load balancer name used to derive a unique access log bucket"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "region" {
  type        = string
  description = "AWS region containing the Network Load Balancer"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}
