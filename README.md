# Self-Hosted GitLab on AWS

Terraform infrastructure for deploying a self-hosted GitLab instance on AWS with a security-hardened, air-gapped network design. Access is provided exclusively through Tailscale VPN — there is no public-facing endpoint.

![Architecture Diagram](docs/architecture.png)

## Architecture Overview

GitLab runs on a single EC2 instance inside private subnets with no direct internet ingress. Developers connect through Tailscale VPN to an internal Application Load Balancer, which terminates TLS 1.3 and forwards traffic to the GitLab instance over HTTP. Outbound internet access (for package updates and Tailscale coordination) is routed through a NAT Gateway in the public subnets.

AWS service access from the private subnets is handled via VPC endpoints (S3, SSM, Secrets Manager, CloudWatch Logs), minimizing traffic that traverses the NAT Gateway. All data is encrypted at rest using KMS or AES-256, and all S3 buckets have public access blocked with lifecycle policies that transition objects to Glacier.

## Modules

### `networking`

VPC, subnets, route tables, NAT Gateway, security groups, VPC endpoints, and flow logs.

- VPC (`10.0.0.0/16`) with DNS hostnames enabled
- 2 public subnets and 2 private subnets across 2 AZs
- NAT Gateway (single AZ) with Elastic IP for outbound from private subnets
- Internet Gateway for the public subnets
- Security groups for the ALB, GitLab EC2, and VPC endpoints
- VPC interface endpoints: SSM, SSM Messages, EC2 Messages, Secrets Manager, CloudWatch Logs
- S3 gateway endpoint via route table
- VPC flow logs to S3

### `gitlab`

EC2 instance, EBS volumes, IAM role, S3 backup bucket, and Secrets Manager secrets.

- `t3.xlarge` EC2 instance running Amazon Linux 2023
- 50 GB encrypted root volume + 100 GB encrypted gp3 data volume (`/var/opt/gitlab`)
- IMDSv2 enforced, detailed monitoring enabled
- IAM instance profile with policies for SSM, S3 backups, Secrets Manager, and CloudWatch Logs
- S3 backup bucket with versioning, KMS encryption, and Glacier lifecycle
- Secrets Manager entries for root password, OAuth credentials, Tailscale auth key, and `gitlab-secrets.json`

### `alb`

Internal Application Load Balancer, target group, HTTPS listener, ACM certificate, and access logging.

- Internal ALB spanning 2 private subnets
- HTTPS listener on port 443 with TLS 1.3 policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`)
- ACM certificate with DNS validation in a cross-account Route 53 zone
- Target group forwarding HTTP port 80 with health checks on `/-/health`
- Access logs to a dedicated S3 bucket with Glacier lifecycle
- Deletion protection enabled

### `dns`

Private Route 53 hosted zone and DNS record for GitLab.

- Private hosted zone associated with the VPC
- A record aliasing the GitLab domain to the internal ALB

### `monitoring`

CloudTrail and CloudWatch alarms.

- CloudTrail logging to S3 with log file validation and Glacier lifecycle
- CloudWatch alarms for CPU utilization (>90% for 15 min) and EC2 status check failures

## Prerequisites

- AWS account with appropriate permissions
- Terraform >= 1.0
- A domain name and Route 53 hosted zone in a DNS account
- An IAM role ARN for cross-account DNS access
- Google OAuth credentials (for GitLab SSO)
- Tailscale auth key

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars  # edit with your values
terraform init
terraform plan
terraform apply
```

Connect to the instance via SSM:

```bash
aws ssm start-session --target <instance-id>
```

## Outputs

| Output | Description |
|--------|-------------|
| `gitlab_instance_id` | EC2 instance ID |
| `gitlab_private_ip` | Private IP address |
| `alb_dns_name` | Internal ALB DNS name |
| `gitlab_url` | GitLab URL (`https://<domain>`) |
| `backup_bucket` | S3 backup bucket name |
| `ssm_connect_command` | SSM session command |
