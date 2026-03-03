variable "project_name" {
  type = string
}

variable "gitlab_instance_id" {
  description = "EC2 instance ID for CloudWatch alarms"
  type        = string
  default     = "" # Empty until EC2 module is wired
}
