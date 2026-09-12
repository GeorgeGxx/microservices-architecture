variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "origin_domain_name" {
  description = "Domain name of the origin (e.g. S3 bucket regional domain name or ALB DNS name)"
  type        = string
}

variable "origin_id" {
  description = "Unique identifier for the origin"
  type        = string
  default     = "primaryOrigin"
}

variable "aliases" {
  description = "Extra CNAMEs (alternate domain names) for the distribution"
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN (must be in us-east-1 for CloudFront). If null, cloudfront_default_certificate is used."
  type        = string
  default     = null
}

variable "price_class" {
  description = "Price class for the distribution (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
