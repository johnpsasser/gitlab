output "gitlab_instance_id" {
  description = "GitLab EC2 instance ID"
  value       = module.gitlab.instance_id
}

output "gitlab_private_ip" {
  description = "GitLab EC2 private IP"
  value       = module.gitlab.instance_private_ip
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "gitlab_url" {
  description = "GitLab URL"
  value       = "https://${var.domain_name}"
}

output "backup_bucket" {
  description = "S3 backup bucket name"
  value       = module.gitlab.backup_bucket_name
}

output "ssm_connect_command" {
  description = "Command to connect via SSM"
  value       = "aws ssm start-session --target ${module.gitlab.instance_id}"
}

output "acm_validation_records" {
  description = "DNS validation records for ACM certificate (create these in Cloudflare)"
  value       = module.alb.acm_validation_records
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications"
  value       = module.monitoring.sns_topic_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
