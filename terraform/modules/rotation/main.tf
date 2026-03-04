################################################################################
# Secrets Rotation Lambda -- GitLab Root Password (IA-5(1))
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- Lambda Security Group ---

resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-rotation-lambda-"
  description = "Security group for secrets rotation Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS outbound to AWS services (SSM, Secrets Manager, KMS)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rotation-lambda-sg"
  }
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_338:Lambda log retention of 90 days is sufficient for operational diagnostics
  name              = "/aws/lambda/${var.project_name}-secrets-rotation"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-rotation-logs"
  }
}

# --- IAM Role ---

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-rotation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-rotation-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-rotation-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.root_password_secret_arn
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "SSMRunCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}::document/AWS-RunShellScript",
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${var.gitlab_instance_id}"
        ]
      },
      {
        Sid    = "SSMParameterForPasswordHandoff"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/rotation/*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# --- Lambda Function ---

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/rotate_gitlab_root_password.py"
  output_path = "${path.module}/lambda/rotate_gitlab_root_password.zip"
}

resource "aws_lambda_function" "rotation" {
  #checkov:skip=CKV_AWS_272:Code signing not required for internal Lambda functions
  function_name = "${var.project_name}-secrets-rotation"
  kms_key_arn   = var.kms_key_arn
  role          = aws_iam_role.lambda.arn
  handler       = "rotate_gitlab_root_password.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      GITLAB_INSTANCE_ID = var.gitlab_instance_id
      PROJECT_NAME       = var.project_name
    }
  }

  reserved_concurrent_executions = 1

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = var.sns_topic_arn
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Name = "${var.project_name}-secrets-rotation"
  }
}

# --- Secrets Manager Rotation Configuration ---

resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = var.root_password_secret_arn
}

resource "aws_secretsmanager_secret_rotation" "root_password" {
  #checkov:skip=CKV_AWS_304:Rotation schedule is configured at 90 days -- meets IA-5(1) requirement
  secret_id           = var.root_password_secret_arn
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}
