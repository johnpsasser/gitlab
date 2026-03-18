variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "gitlab_instance_id" {
  type = string
}

variable "s3_access_logs_bucket_id" {
  description = "S3 bucket ID for access logging"
  type        = string
}
