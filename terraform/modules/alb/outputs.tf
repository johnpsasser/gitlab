output "alb_dns_name" {
  value = aws_lb.gitlab.dns_name
}

output "alb_zone_id" {
  value = aws_lb.gitlab.zone_id
}

output "alb_arn" {
  value = aws_lb.gitlab.arn
}
