resource "aws_guardduty_detector" "main" {
  #checkov:skip=CKV2_AWS_3:GuardDuty organization-wide enablement not applicable -- standalone account deployment
  enable = true

  tags = {
    Name = "${var.project_name}-guardduty"
  }
}

resource "aws_guardduty_detector_feature" "s3_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}
