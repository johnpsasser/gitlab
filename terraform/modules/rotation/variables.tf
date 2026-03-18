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

variable "gitlab_instance_id" {
  description = "GitLab EC2 instance ID for SSM Run Command"
  type        = string
}

variable "root_password_secret_arn" {
  description = "ARN of the GitLab root password Secrets Manager secret"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "rotation_days" {
  description = "Number of days between automatic password rotations"
  type        = number
  default     = 90
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for dead letter queue"
  type        = string
}
