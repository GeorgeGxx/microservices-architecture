variable "repository_names" {
  description = "List of ECR repository names to create, one per microservice"
  type        = list(string)
  default = [
    "apollo-router",
    "inventory-service",
    "notification-service",
    "orders-service",
    "products-service",
    "frontend",
  ]
}

variable "environment" {
  type = string
}

variable "image_tag_mutability" {
  type    = string
  default = "IMMUTABLE"
}

variable "scan_on_push" {
  type    = bool
  default = true
}

variable "max_image_count" {
  description = "Lifecycle policy: keep only the N most recent images"
  type        = number
  default     = 15
}

variable "tags" {
  type    = map(string)
  default = {}
}
