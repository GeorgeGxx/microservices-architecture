variable "bucket_name" {
  type        = string
  description = "Globally unique name for the S3 bucket storing Terraform remote state."
}

variable "dynamodb_table_name" {
  type        = string
  description = "Name for the DynamoDB table managing Terraform state locks."
}

variable "environment" {
  type        = string
  description = "Target environment name (staging, prod)."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Optional ARN of customer-managed KMS key for encryption. Defaults to AWS managed SSE-S3/KMS."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Whether to allow force destroy of the S3 bucket. Should be false for staging and prod."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to S3 bucket and DynamoDB table."
}
