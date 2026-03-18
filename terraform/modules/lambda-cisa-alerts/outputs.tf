output "lambda_arn" {
  description = "ARN of the CISA alerts Lambda function"
  value       = aws_lambda_function.cisa_alerts.arn
}
