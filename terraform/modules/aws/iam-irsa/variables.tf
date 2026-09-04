variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_issuer_url" {
  description = "Issuer URL without the https:// prefix, e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX"
  type        = string
}

variable "namespace" {
  type    = string
  default = "default"
}

variable "service_account_name" {
  type = string
}

variable "policy_arns" {
  description = "IAM managed policy ARNs to attach (e.g. for S3, SQS, SES access from pods)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the IAM resources"
  type        = map(string)
  default     = {}
}

