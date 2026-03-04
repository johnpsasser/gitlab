output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.gitlab.zone_id
}

output "nameservers" {
  description = "Nameservers for the hosted zone (add these as NS records in the parent zone)"
  value       = aws_route53_zone.gitlab.name_servers
}

output "validated_certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.gitlab.certificate_arn
}
