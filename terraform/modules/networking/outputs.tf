output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "gitlab_security_group_id" {
  value = aws_security_group.gitlab.id
}

output "s3_access_logs_bucket_id" {
  value = aws_s3_bucket.access_logs.id
}
