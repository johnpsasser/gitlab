output "rotation_lambda_arn" {
  description = "ARN of the secrets rotation Lambda function"
  value       = aws_lambda_function.rotation.arn
}

output "security_group_id" {
  description = "Security group ID for the rotation Lambda"
  value       = aws_security_group.lambda.id
}
