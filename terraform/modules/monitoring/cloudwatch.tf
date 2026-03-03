resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.gitlab_instance_id != "" ? 1 : 0

  alarm_name          = "${var.project_name}-gitlab-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "GitLab EC2 CPU > 90% for 15 minutes"

  dimensions = {
    InstanceId = var.gitlab_instance_id
  }

  tags = {
    Name = "${var.project_name}-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  count = var.gitlab_instance_id != "" ? 1 : 0

  alarm_name          = "${var.project_name}-gitlab-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "GitLab EC2 status check failed"

  dimensions = {
    InstanceId = var.gitlab_instance_id
  }

  tags = {
    Name = "${var.project_name}-status-check-alarm"
  }
}
