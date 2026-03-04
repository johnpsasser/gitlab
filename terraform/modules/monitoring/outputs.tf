output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_bucket" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerting topic"
  value       = aws_sns_topic.alerts.arn
}
