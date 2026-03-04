data "aws_caller_identity" "current" {}

module "flow_logs_bucket" {
  source = "../s3-bucket"

  project_name             = var.project_name
  bucket_purpose           = "flow-logs"
  kms_key_arn              = var.kms_key_arn
  enable_versioning        = true
  glacier_transition_days  = 30
  expiration_days          = 365
  logging_target_bucket_id = aws_s3_bucket.access_logs.id
  logging_target_prefix    = "flow-logs/"
  enable_logging           = true

  additional_policy_statements = jsonencode([
    {
      Sid    = "AWSLogDeliveryAclCheck"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:GetBucketAcl"
      Resource = "SELF_BUCKET_ARN"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    },
    {
      Sid    = "AWSLogDeliveryWrite"
      Effect = "Allow"
      Principal = {
        Service = "delivery.logs.amazonaws.com"
      }
      Action   = "s3:PutObject"
      Resource = "SELF_BUCKET_ARN/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl"      = "bucket-owner-full-control"
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }
  ])
}

# VPC Flow Logs
resource "aws_flow_log" "vpc" {
  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = module.flow_logs_bucket.bucket_arn
  max_aggregation_interval = 60

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}
