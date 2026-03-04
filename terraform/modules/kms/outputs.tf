################################################################################
# General Key
################################################################################

output "general_key_arn" {
  description = "ARN of the general-purpose KMS key"
  value       = aws_kms_key.general.arn
}

output "general_key_id" {
  description = "ID of the general-purpose KMS key"
  value       = aws_kms_key.general.key_id
}

################################################################################
# CloudTrail Key
################################################################################

output "cloudtrail_key_arn" {
  description = "ARN of the CloudTrail KMS key"
  value       = aws_kms_key.cloudtrail.arn
}

output "cloudtrail_key_id" {
  description = "ID of the CloudTrail KMS key"
  value       = aws_kms_key.cloudtrail.key_id
}

################################################################################
# EBS Key
################################################################################

output "ebs_key_arn" {
  description = "ARN of the EBS KMS key"
  value       = aws_kms_key.ebs.arn
}

output "ebs_key_id" {
  description = "ID of the EBS KMS key"
  value       = aws_kms_key.ebs.key_id
}
