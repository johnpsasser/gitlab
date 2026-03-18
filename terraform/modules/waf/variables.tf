variable "project_name" {
  type = string
}

variable "alb_arn" {
  description = "ARN of the ALB to associate with WAF"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting WAF log group"
  type        = string
}
