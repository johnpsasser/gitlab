variable "project_name" {
  type = string
}

variable "domain_name" {
  description = "Domain name for GitLab (e.g., code.agiledefense.xyz)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB"
  type        = string
}

variable "alb_zone_id" {
  description = "Route53 zone ID of the ALB (for alias records)"
  type        = string
}

variable "acm_domain_validation_options" {
  description = "ACM certificate domain validation options"
  type = list(object({
    domain_name           = string
    resource_record_name  = string
    resource_record_type  = string
    resource_record_value = string
  }))
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate to validate"
  type        = string
}
