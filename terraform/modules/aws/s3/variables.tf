variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "bucket_name_override" {
  description = "Optional explicit bucket name override. If null, derived from name and environment"
  type        = string
  default     = null
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for SSE-KMS encryption. If null, AES256 is used."
  type        = string
  default     = null
}

variable "enable_versioning" {
  description = "Enable versioning for the S3 bucket"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Whether to allow bucket deletion even if non-empty (useful in dev)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
