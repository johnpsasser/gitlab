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

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = aws_acm_certificate.gitlab.arn
}

output "acm_domain_validation_options" {
  description = "ACM certificate domain validation options for Route53"
  value       = aws_acm_certificate.gitlab.domain_validation_options
}

output "alb_arn_suffix" {
  description = "ARN suffix of the ALB for CloudWatch metrics"
  value       = aws_lb.gitlab.arn_suffix
}

output "target_group_arn_suffix" {
  description = "ARN suffix of the ALB target group for CloudWatch metrics"
  value       = aws_lb_target_group.gitlab.arn_suffix
}
