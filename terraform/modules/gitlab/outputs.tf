output "iam_role_arn" {
  value = aws_iam_role.gitlab.arn
}

output "backup_bucket_name" {
  value = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backups.arn
}
