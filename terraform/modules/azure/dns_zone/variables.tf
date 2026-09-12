variable "domain_name" {
  description = "The DNS zone domain name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "target_ip" {
  description = "Optional Public IP to point the A record to (e.g. App Gateway Public IP)"
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
