variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT (use SPOT for dev to cut cost)"
  type        = string
  default     = "ON_DEMAND"
}

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "kms_key_arn" {
  description = "Custom KMS Key ARN for EKS secret encryption. If null, a managed key will be created."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
