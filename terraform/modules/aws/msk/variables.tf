variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the MSK cluster will be deployed"
  type        = string
}

variable "client_subnet_ids" {
  description = "List of private subnet IDs for MSK broker placement across AZs"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to MSK Kafka brokers (e.g. EKS node SG)"
  type        = list(string)
  default     = []
}

variable "kafka_version" {
  description = "Desired Apache Kafka version"
  type        = string
  default     = "3.6.0"
}

variable "number_of_broker_nodes" {
  description = "Total number of broker nodes in the cluster (must be multiple of number of AZs)"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "Broker instance type (e.g. kafka.t3.small for dev/staging, kafka.m5.large for prod)"
  type        = string
  default     = "kafka.t3.small"
}

variable "ebs_volume_size" {
  description = "The size in GiB of the EBS volume for the data drive on each broker node"
  type        = number
  default     = 50
}

variable "kms_key_arn" {
  description = "KMS Key ARN for encryption at rest"
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
