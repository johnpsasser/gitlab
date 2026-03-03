data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "gitlab" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

resource "aws_iam_instance_profile" "gitlab" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.gitlab.name
}

# SSM Session Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gitlab.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Secrets Manager read access
resource "aws_iam_role_policy" "secrets" {
  name = "${var.project_name}-secrets-access"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"
      }
    ]
  })
}

# S3 backup access
resource "aws_iam_role_policy" "s3_backup" {
  name = "${var.project_name}-s3-backup"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-backups-*",
          "arn:aws:s3:::${var.project_name}-backups-*/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.project_name}-cloudwatch"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/*"
      }
    ]
  })
}
