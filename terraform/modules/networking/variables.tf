variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting S3 buckets"
  type        = string
}
