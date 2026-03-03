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

variable "google_oauth_hd" {
  type = string
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  type        = string
  default     = "" # Set after backup module creates the bucket
}
