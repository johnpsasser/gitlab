output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.gitlab.dns_name
}

output "alb_zone_id" {
  description = "Route 53 zone ID of the ALB"
  value       = aws_lb.gitlab.zone_id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.gitlab.arn
}

output "acm_validation_records" {
  description = "DNS validation records to create in Cloudflare for ACM certificate"
  value = {
    for dvo in aws_acm_certificate.gitlab.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB for CloudWatch metrics"
  value       = aws_lb.gitlab.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the ALB target group for CloudWatch metrics"
  value       = aws_lb_target_group.gitlab.arn_suffix
}
