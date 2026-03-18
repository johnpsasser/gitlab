################################################################################
# EventBridge Schedule -- Daily CISA KEV Check (SI-5)
################################################################################

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${var.project_name}-cisa-alerts-daily"
  description         = "Trigger CISA KEV advisory check Lambda daily"
  schedule_expression = "cron(0 6 * * ? *)"

  tags = {
    Name = "${var.project_name}-cisa-alerts-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.daily.name
  arn  = aws_lambda_function.cisa_alerts.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cisa_alerts.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}

# --- Lambda Error Alarm ---

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-cisa-alerts-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "CISA alerts Lambda function errors"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    FunctionName = aws_lambda_function.cisa_alerts.function_name
  }

  tags = {
    Name = "${var.project_name}-cisa-alerts-error-alarm"
  }
}
