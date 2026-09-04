variable "environment" {
  type        = string
  description = "Target deployment environment (dev, staging, prod)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in format organization/repository (e.g. georgegxx/microservices-architecture)"
  default     = "*/*"
}

variable "create_oidc_provider" {
  type        = bool
  description = "Whether to create the AWS IAM OIDC provider if not already present in the account"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}
