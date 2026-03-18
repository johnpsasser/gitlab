variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Lambda networking"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda ENIs"
  type        = list(string)
}

variable "domain_name" {
  description = "GitLab domain name (e.g., gitlab.example.com)"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Lambda environment variables and CloudWatch Logs"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for Secrets Manager encryption"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for deactivation notifications"
  type        = string
}

variable "inactive_days" {
  description = "Number of days of inactivity before account deactivation"
  type        = number
  default     = 90
}

variable "dry_run" {
  description = "When true, log actions without deactivating users"
  type        = bool
  default     = true
}
