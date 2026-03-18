data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"] # Amazon's verified AMI publisher account

  filter {
    name   = "name"
    values = [var.use_fips_ami ? "al2023-ami-*-fips-*-x86_64" : "al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "gitlab" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.gitlab.name
  monitoring             = true
  ebs_optimized          = true

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.ebs_kms_key_id
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    region        = data.aws_region.current.name
    project_name  = var.project_name
    domain_name   = var.domain_name
    backup_bucket = aws_s3_bucket.backups.id
    cloudwatch_agent_config = templatefile("${path.module}/templates/cloudwatch-agent-config.json.tpl", {
      project_name = var.project_name
    })
  })

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  tags = {
    Name       = "${var.project_name}-ec2"
    PatchGroup = var.project_name
    Backup     = "true"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Separate data volume for /var/opt/gitlab
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.gitlab.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true
  kms_key_id        = var.ebs_kms_key_id

  tags = {
    Name   = "${var.project_name}-data"
    Backup = "true"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.gitlab.id
}
