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

variable "s3_access_logs_bucket_id" {
  description = "S3 bucket ID for access logging"
  type        = string
}

variable "use_fips_ami" {
  description = "Use FIPS-validated Amazon Linux 2023 AMI for IL2 compliance"
  type        = bool
  default     = false
}

variable "ami_id" {
  description = "Optional override AMI ID (e.g., for pinned FIPS AMI). If set, overrides the AMI data source."
  type        = string
  default     = ""
}

variable "backup_replication_region" {
  description = "AWS region for backup cross-region replication"
  type        = string
  default     = ""
}

variable "enable_backup_replication" {
  description = "Enable cross-region S3 replication for backups"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for patching notifications"
  type        = string
  default     = ""
}
