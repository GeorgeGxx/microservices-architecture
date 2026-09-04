variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (leave empty for HTTP-only dev)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
