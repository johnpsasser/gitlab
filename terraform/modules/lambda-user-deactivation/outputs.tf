output "lambda_arn" {
  description = "ARN of the user deactivation Lambda function"
  value       = aws_lambda_function.user_deactivation.arn
}

output "security_group_id" {
  description = "Security group ID for the Lambda function"
  value       = aws_security_group.lambda.id
}

output "secret_arn" {
  description = "ARN of the GitLab admin PAT secret"
  value       = aws_secretsmanager_secret.gitlab_admin_pat.arn
}
