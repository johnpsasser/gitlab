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
