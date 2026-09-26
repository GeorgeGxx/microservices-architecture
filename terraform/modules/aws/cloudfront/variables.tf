variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "s3_bucket_domain_name" {
  description = "Regional domain name of the S3 bucket serving the React 19 static frontend"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket serving static frontend assets (for CloudFront OAC policy)"
  type        = string
}

variable "s3_bucket_id" {
  description = "ID / Name of the S3 bucket serving static assets"
  type        = string
}

variable "api_origin_domain_name" {
  description = "Domain name of the backend API origin (AWS NLB DNS name fronting the Istio ingress gateway)"
  type        = string
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
