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
  description = "Amazon MSK Provisioned Kafka version. 4.1.x is the closest currently supported MSK Provisioned line to local Confluent Platform 8.3.x (Apache Kafka 4.3.x)."
  type        = string
  default     = "4.1.x"
}

variable "number_of_broker_nodes" {
  description = "Total number of broker nodes in the cluster (must be multiple of number of AZs)"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "MSK Standard broker type. Kafka 4.x uses KRaft, which requires an M5 or M7g broker (T3 is unsupported)."
  type        = string
  default     = "kafka.m5.large"
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
