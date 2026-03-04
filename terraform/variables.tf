variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region code (e.g., us-east-1)."
  }
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

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "domain_name" {
  description = "Domain name for GitLab (e.g., gitlab.yourcompany.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain_name))
    error_message = "domain_name must be a valid domain name."
  }
}

variable "instance_type" {
  description = "EC2 instance type for GitLab"
  type        = string
  default     = "t3.xlarge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type (e.g., t3.xlarge)."
  }
}

variable "data_volume_size" {
  description = "Size in GB for GitLab data EBS volume"
  type        = number
  default     = 100

  validation {
    condition     = var.data_volume_size >= 50 && var.data_volume_size <= 16384
    error_message = "data_volume_size must be between 50 and 16384 GB."
  }
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

variable "use_fips_ami" {
  description = "Use FIPS-validated Amazon Linux 2023 AMI for IL2 compliance (SC-13). Set to true for production IL2 deployments."
  type        = bool
  default     = false # Default false for dev/test; set true in production tfvars
}

variable "enable_backup_replication" {
  description = "Enable cross-region S3 replication for backups (CP-6)"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for SNS alarm notifications (must confirm subscription after apply)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}
