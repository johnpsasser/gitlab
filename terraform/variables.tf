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

variable "dns_account_role_arn" {
  description = "IAM role ARN in the DNS account for cross-account Route 53 access"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID in the DNS account for ACM validation"
  type        = string
}

variable "google_oauth_hd" {
  description = "Google Workspace hosted domain for OAuth restriction"
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
