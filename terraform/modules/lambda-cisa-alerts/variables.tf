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

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudWatch Logs and DynamoDB"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CISA alert notifications"
  type        = string
}
