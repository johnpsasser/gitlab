resource "aws_route53_zone" "gitlab" {
  name = var.domain_name

  tags = {
    Name = "${var.project_name}-zone"
  }
}

# Alias A record: domain -> ALB
resource "aws_route53_record" "gitlab_alb" {
  zone_id = aws_route53_zone.gitlab.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ACM DNS validation records
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in var.acm_domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.gitlab.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 300
  records         = [each.value.record]
  allow_overwrite = true
}

# Wait for ACM certificate to be validated
resource "aws_acm_certificate_validation" "gitlab" {
  certificate_arn         = var.acm_certificate_arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
