variable "environment" {
  type        = string
  description = "Target deployment environment (dev, staging, prod)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository in format organization/repository (e.g. GeorgeGxx/microservices-architecture)"
  default     = "GeorgeGxx/microservices-architecture"
}

variable "allowed_subjects" {
  type        = list(string)
  description = "Explicit OIDC sub claim patterns allowed to assume the role. If empty, defaults to environment-scoped branch/environment claims."
  default     = []
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
