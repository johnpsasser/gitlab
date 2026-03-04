resource "aws_acm_certificate" "gitlab" {
  domain_name       = var.domain_name
  validation_method = "EMAIL"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}
