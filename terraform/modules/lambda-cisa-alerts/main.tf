################################################################################
# CISA KEV Advisory Subscription Lambda (SI-5)
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- DynamoDB State Table ---

resource "aws_dynamodb_table" "cisa_state" {
  #checkov:skip=CKV_AWS_28:Point-in-time recovery not needed for simple state tracking
  #checkov:skip=CKV_AWS_119:KMS encryption used via server_side_encryption block
  name         = "${var.project_name}-cisa-kev-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = {
    Name = "${var.project_name}-cisa-kev-state"
  }
}

# --- Lambda Security Group ---

resource "aws_security_group" "lambda" {
  name_prefix = "${var.project_name}-cisa-alerts-lambda-"
  description = "Security group for CISA alerts Lambda"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS outbound to CISA and AWS services"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-cisa-alerts-lambda-sg"
  }
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_338:Lambda log retention of 90 days is sufficient for operational diagnostics
  name              = "/aws/lambda/${var.project_name}-cisa-alerts"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "${var.project_name}-cisa-alerts-logs"
  }
}

# --- IAM Role ---

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-cisa-alerts-lambda-role"

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
    Name = "${var.project_name}-cisa-alerts-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project_name}-cisa-alerts-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.cisa_state.arn
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
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/src/handler.zip"
}

resource "aws_lambda_function" "cisa_alerts" {
  #checkov:skip=CKV_AWS_272:Code signing not required for internal Lambda functions
  function_name = "${var.project_name}-cisa-alerts"
  kms_key_arn   = var.kms_key_arn
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.cisa_state.name
      SNS_TOPIC_ARN  = var.sns_topic_arn
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
    Name = "${var.project_name}-cisa-alerts"
  }
}
