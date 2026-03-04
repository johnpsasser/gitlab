resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:GuardDuty organization-wide enablement not applicable — standalone account deployment
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
  }

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}
