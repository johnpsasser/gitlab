variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting Config delivery S3 bucket"
  type        = string
}
