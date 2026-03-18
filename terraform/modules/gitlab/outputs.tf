output "instance_id" {
  description = "ID of the GitLab EC2 instance"
  value       = aws_instance.gitlab.id
}

output "instance_private_ip" {
  description = "Private IP address of the GitLab EC2 instance"
  value       = aws_instance.gitlab.private_ip
}

output "iam_role_arn" {
  description = "ARN of the GitLab EC2 IAM role"
  value       = aws_iam_role.gitlab.arn
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = aws_s3_bucket.backups.arn
}

output "root_password_secret_arn" {
  description = "ARN of the root password Secrets Manager secret"
  value       = aws_secretsmanager_secret.root_password.arn
}
