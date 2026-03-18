variable "project_name" {
  type = string
}

variable "gitlab_instance_id" {
  description = "EC2 instance ID for CloudWatch alarms"
  type        = string
}

variable "enable_instance_alarms" {
  description = "Whether to create EC2 instance-based CloudWatch alarms"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting monitoring resources"
  type        = string
}

variable "cloudtrail_kms_key_arn" {
  description = "KMS key ARN for CloudTrail encryption"
  type        = string
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications (must confirm subscription after apply)"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB for CloudWatch alarms"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the ALB target group for CloudWatch alarms"
  type        = string
}

variable "enable_alb_alarms" {
  description = "Whether to create ALB-based CloudWatch alarms"
  type        = bool
  default     = true
}
