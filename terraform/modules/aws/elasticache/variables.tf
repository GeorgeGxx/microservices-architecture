variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ElastiCache cluster is deployed"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the ElastiCache subnet group (private subnets)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access Redis on port 6379 (e.g. EKS worker nodes)"
  type        = list(string)
  default     = []
}

variable "node_type" {
  description = "ElastiCache instance class (e.g. cache.t4g.micro, cache.t4g.small, cache.m6g.large)"
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (primary + replicas). 1 for dev, 2+ for staging/prod"
  type        = number
  default     = 1
}

variable "automatic_failover_enabled" {
  description = "Whether automatic failover is enabled (requires num_cache_clusters > 1)"
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "Specifies whether to enable Multi-AZ support"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS Key ARN for at-rest encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
