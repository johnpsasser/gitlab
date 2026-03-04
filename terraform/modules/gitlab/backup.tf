resource "aws_s3_bucket" "backups" {
  #checkov:skip=CKV_AWS_144:S3 cross-region replication not needed for log/state buckets (backups handled separately)
  #checkov:skip=CKV2_AWS_62:S3 event notifications not required for this deployment
  bucket_prefix = "${var.project_name}-backups-"

  tags = {
    Name = "${var.project_name}-backups"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_logging" "backups" {
  bucket        = aws_s3_bucket.backups.id
  target_bucket = var.s3_access_logs_bucket_id
  target_prefix = "gitlab-backups/"
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "glacier-transition"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
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

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Cross-region replication IAM role (CP-6)
resource "aws_iam_role" "replication" {
  count = var.enable_backup_replication ? 1 : 0
  name  = "${var.project_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_backup_replication ? 1 : 0
  name  = "${var.project_name}-s3-replication-policy"
  role  = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.backups.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.backup_replica[0].arn}/*"
      }
    ]
  })
}

# Replica bucket (in replication region)
resource "aws_s3_bucket" "backup_replica" {
  #checkov:skip=CKV_AWS_18:Access logging not configured for replica bucket in secondary region (no log target)
  #checkov:skip=CKV2_AWS_62:S3 event notifications not required for backup replica
  #checkov:skip=CKV_AWS_144:Cross-region replication not needed on the replica itself
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication

  bucket_prefix = "${var.project_name}-backups-replica-"

  tags = {
    Name = "${var.project_name}-backups-replica"
  }
}

resource "aws_s3_bucket_versioning" "backup_replica" {
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication
  bucket   = aws_s3_bucket.backup_replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_replica" {
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication
  bucket   = aws_s3_bucket.backup_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup_replica" {
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication
  bucket   = aws_s3_bucket.backup_replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_replica" {
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication
  bucket   = aws_s3_bucket.backup_replica[0].id

  rule {
    id     = "archive"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
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

resource "aws_s3_bucket_policy" "backup_replica" {
  count    = var.enable_backup_replication ? 1 : 0
  provider = aws.replication
  bucket   = aws_s3_bucket.backup_replica[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backup_replica[0].arn,
          "${aws_s3_bucket.backup_replica[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Replication configuration on the source bucket
resource "aws_s3_bucket_replication_configuration" "backups" {
  count  = var.enable_backup_replication ? 1 : 0
  bucket = aws_s3_bucket.backups.id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "backup-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.backup_replica[0].arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}
