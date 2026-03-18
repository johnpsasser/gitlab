variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "bucket_purpose" {
  description = "Purpose of the bucket (used in naming, e.g., 'backups', 'flow-logs')"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for server-side encryption. Empty string uses AES256."
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable versioning on the bucket"
  type        = bool
  default     = true
}

variable "glacier_transition_days" {
  description = "Days before objects transition to Glacier"
  type        = number
  default     = 30
}

variable "expiration_days" {
  description = "Days before objects expire"
  type        = number
  default     = 365
}

variable "logging_target_bucket_id" {
  description = "Target bucket ID for access logging. Empty to disable."
  type        = string
  default     = ""
}

variable "enable_logging" {
  description = "Whether to enable S3 access logging"
  type        = bool
  default     = false
}

variable "logging_target_prefix" {
  description = "Prefix for access log objects"
  type        = string
  default     = ""
}

variable "additional_policy_statements" {
  description = "Additional IAM policy statements to include in the bucket policy (as JSON-encoded list)"
  type        = string
  default     = "[]"
}

variable "tags" {
  description = "Additional tags for the bucket"
  type        = map(string)
  default     = {}
}
