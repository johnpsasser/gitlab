resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Security group for GitLab ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC (Tailscale traffic)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "gitlab" {
  name_prefix = "${var.project_name}-gitlab-"
  description = "Security group for GitLab EC2 instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from VPC (Git over SSH via Tailscale)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS outbound (updates, Tailscale coordination)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound (package repos)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-gitlab-sg"
  }
}

# Standalone rules to break the circular dependency between ALB and GitLab SGs
resource "aws_security_group_rule" "alb_to_gitlab" {
  type                     = "egress"
  description              = "HTTP to GitLab"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.gitlab.id
}

resource "aws_security_group_rule" "gitlab_from_alb" {
  type                     = "ingress"
  description              = "HTTP from ALB"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.gitlab.id
  source_security_group_id = aws_security_group.alb.id
}
