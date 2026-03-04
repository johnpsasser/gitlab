################################################################################
# EventBridge Schedule -- Weekly User Deactivation (AC-2(3))
################################################################################

resource "aws_cloudwatch_event_rule" "weekly" {
  name                = "${var.project_name}-user-deactivation-weekly"
  description         = "Trigger inactive user deactivation Lambda weekly"
  schedule_expression = "cron(0 2 ? * SUN *)"

  tags = {
    Name = "${var.project_name}-user-deact-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.weekly.name
  arn  = aws_lambda_function.user_deactivation.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.user_deactivation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly.arn
}

# --- Lambda Error Alarm ---

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-user-deact-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "User deactivation Lambda function errors"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    FunctionName = aws_lambda_function.user_deactivation.function_name
  }

  tags = {
    Name = "${var.project_name}-user-deact-error-alarm"
  }
}
