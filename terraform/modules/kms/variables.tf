variable "project_name" {
  description = "Project name used for key aliases and resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used in CloudTrail key policy source ARN condition)"
  type        = string
}
