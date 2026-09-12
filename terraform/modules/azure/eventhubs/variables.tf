variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "location" {
  description = "Azure region location"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "sku" {
  description = "Defines which tier to use for Event Hubs Namespace (Standard or Premium for Kafka support)"
  type        = string
  default     = "Standard"
}

variable "capacity" {
  description = "Specifies the Capacity / Throughput Units"
  type        = number
  default     = 1
}

variable "partition_count" {
  description = "Number of partitions for the orders-topic"
  type        = number
  default     = 2
}

variable "message_retention" {
  description = "Number of days to retain the events for this Event Hub"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
