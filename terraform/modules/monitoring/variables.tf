variable "project_name" {
  type = string
}

variable "gitlab_instance_id" {
  description = "EC2 instance ID for CloudWatch alarms"
  type        = string
  default     = "" # Empty until EC2 module is wired
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
  description = "Email address for SNS alarm notifications (empty to skip subscription)"
  type        = string
  default     = ""
}
