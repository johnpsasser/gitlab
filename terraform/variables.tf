variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "gitlab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_name" {
  description = "Domain name for GitLab (e.g., gitlab.yourcompany.com)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for GitLab"
  type        = string
  default     = "t3.xlarge"
}

variable "data_volume_size" {
  description = "Size in GB for GitLab data EBS volume"
  type        = number
  default     = 100
}

variable "backup_replication_region" {
  description = "AWS region for backup cross-region replication"
  type        = string
  default     = "us-west-2"
}

variable "data_classification" {
  description = "DoD data classification level"
  type        = string
  default     = "IL2"
}
