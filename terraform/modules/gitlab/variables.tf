variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private subnet ID for the GitLab EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the GitLab EC2 instance"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.xlarge"
}

variable "data_volume_size" {
  type    = number
  default = 100
}

variable "domain_name" {
  type = string
}

variable "ebs_kms_key_id" {
  description = "KMS key ID for EBS volume encryption"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for Secrets Manager encryption"
  type        = string
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  type        = string
  default     = "" # Set after backup module creates the bucket
}

variable "s3_access_logs_bucket_id" {
  description = "S3 bucket ID for access logging"
  type        = string
}
