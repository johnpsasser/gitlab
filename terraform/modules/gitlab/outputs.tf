output "instance_id" {
  value = aws_instance.gitlab.id
}

output "instance_private_ip" {
  value = aws_instance.gitlab.private_ip
}

output "iam_role_arn" {
  value = aws_iam_role.gitlab.arn
}

output "backup_bucket_name" {
  value = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backups.arn
}

output "root_password_secret_arn" {
  description = "ARN of the root password Secrets Manager secret"
  value       = aws_secretsmanager_secret.root_password.arn
}
