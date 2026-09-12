variable "name" {
  description = "Base resource name prefix"
  type        = string
}

variable "environment" {
  description = "Target environment (dev, staging, prod)"
  type        = string
}

variable "log_retention_days" {
  description = "Specifies the number of days you want to retain log events"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "KMS Key ARN for encrypting CloudWatch log groups"
  type        = string
  default     = null
}

variable "alarm_evaluation_periods" {
  description = "Number of periods over which data is compared to the specified threshold"
  type        = number
  default     = 2
}

variable "alarm_period_seconds" {
  description = "Period in seconds over which the specified statistic is applied"
  type        = number
  default     = 300
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (e.g. SNS topics)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
