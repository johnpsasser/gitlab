# Reusable S3 bucket module with IL2 security defaults
# Includes: encryption, versioning, public access block, lifecycle, SecureTransport deny

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_144:S3 cross-region replication not needed for log buckets (backups handled separately)
  #checkov:skip=CKV2_AWS_62:S3 event notifications not required for this deployment
  bucket_prefix = "${var.project_name}-${var.bucket_purpose}-"

  tags = merge(
    { Name = "${var.project_name}-${var.bucket_purpose}" },
    var.tags
  )
}

# Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
  }
}

# Versioning (conditional)
resource "aws_s3_bucket_versioning" "this" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Public access block (always enabled)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"
    filter {}

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Access logging (conditional)
resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_target_bucket_id != "" ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket_id
  target_prefix = var.logging_target_prefix != "" ? var.logging_target_prefix : "${var.bucket_purpose}/"
}

# Bucket policy with SecureTransport deny + optional additional statements
# Additional statements may use the placeholder SELF_BUCKET_ARN which is
# replaced with the actual bucket ARN at plan time.
locals {
  base_policy_statements = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }
  ]

  # Replace SELF_BUCKET_ARN placeholder in additional statements with actual ARN
  additional_raw        = replace(var.additional_policy_statements, "SELF_BUCKET_ARN", aws_s3_bucket.this.arn)
  additional_statements = jsondecode(local.additional_raw)
  all_statements        = concat(local.base_policy_statements, local.additional_statements)
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.all_statements
  })
}
