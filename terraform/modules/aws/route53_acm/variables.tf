variable "domain_name" {
  description = "Domain name for Route53 zone and ACM certificate (e.g. msa.example.com)"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "create_zone" {
  description = "Whether to create a new Route53 hosted zone or use existing"
  type        = bool
  default     = true
}

variable "existing_zone_id" {
  description = "Existing Route53 hosted zone ID if create_zone is false"
  type        = string
  default     = null
}

variable "subject_alternative_names" {
  description = "List of SANs to include in the ACM certificate"
  type        = list(string)
  default     = []
}

variable "target_alb_dns_name" {
  description = "Optional ALB DNS name to create apex/subdomain alias record"
  type        = string
  default     = null
}

variable "target_alb_zone_id" {
  description = "Optional ALB Hosted Zone ID for alias record"
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
