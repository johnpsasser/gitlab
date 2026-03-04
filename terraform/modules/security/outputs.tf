output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "config_recorder_id" {
  value = aws_config_configuration_recorder.main.id
}

output "inspector_enabler_id" {
  description = "Inspector v2 enabler resource ID"
  value       = aws_inspector2_enabler.ec2.id
}
