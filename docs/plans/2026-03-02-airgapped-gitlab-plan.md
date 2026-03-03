# Air-Gapped GitLab CE on AWS — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy a production-ready, compliance-informed GitLab CE instance on AWS EC2 behind Tailscale VPN, fully managed by Terraform.

**Architecture:** GitLab Omnibus on EC2 in a private subnet, fronted by an internal ALB with ACM TLS. Access via Tailscale VPN mesh. Google OAuth for authentication. All infrastructure as Terraform with S3/DynamoDB state backend. Compliance-informed: FIPS AMI, CloudTrail, VPC Flow Logs, KMS encryption.

**Tech Stack:** Terraform, AWS (VPC, EC2, ALB, ACM, Route 53, S3, Secrets Manager, CloudTrail, CloudWatch, SSM), GitLab CE Omnibus, Tailscale, Google OAuth

**Design doc:** `docs/plans/2026-03-02-airgapped-gitlab-design.md`

---

## Task 1: Project Scaffolding

**Files:**
- Create: `.gitignore`
- Create: `terraform/bootstrap/state_backend.tf`
- Create: `terraform/bootstrap/README.md`

**Step 1: Create .gitignore**

```gitignore
# Terraform
terraform/.terraform/
terraform/**/.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
.terraform.lock.hcl

# Secrets
*.pem
*.key

# OS
.DS_Store
```

**Step 2: Create the bootstrap Terraform for state backend**

`terraform/bootstrap/state_backend.tf`:
```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  default = "gitlab"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

data "aws_caller_identity" "current" {}

output "state_bucket" {
  value = aws_s3_bucket.terraform_state.id
}

output "lock_table" {
  value = aws_dynamodb_table.terraform_locks.id
}
```

`terraform/bootstrap/README.md`:
```markdown
# Bootstrap

Run once to create the Terraform state backend.

1. `cd terraform/bootstrap`
2. `terraform init`
3. `terraform apply`
4. Note the `state_bucket` and `lock_table` outputs
5. Update `../backend.tf` with these values
```

**Step 3: Validate bootstrap**

Run: `cd terraform/bootstrap && terraform init && terraform validate`
Expected: "Success! The configuration is valid."

**Step 4: Commit**

```bash
git add .gitignore terraform/bootstrap/
git commit -m "Add project scaffolding and state backend bootstrap"
```

---

## Task 2: Terraform Root Configuration

**Files:**
- Create: `terraform/backend.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/outputs.tf`
- Create: `terraform/main.tf`
- Create: `terraform/versions.tf`

**Step 1: Create versions.tf**

`terraform/versions.tf`:
```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

**Step 2: Create backend.tf**

`terraform/backend.tf`:
```hcl
terraform {
  backend "s3" {
    bucket         = "gitlab-terraform-state-ACCOUNT_ID" # Update after bootstrap
    key            = "gitlab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitlab-terraform-locks"
    encrypt        = true
  }
}
```

**Step 3: Create variables.tf**

`terraform/variables.tf`:
```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "gitlab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "domain_name" {
  description = "Domain name for GitLab (e.g., gitlab.yourcompany.com)"
  type        = string
}

variable "dns_account_role_arn" {
  description = "IAM role ARN in the DNS account for cross-account Route 53 access"
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID in the DNS account for ACM validation"
  type        = string
}

variable "google_oauth_hd" {
  description = "Google Workspace hosted domain for OAuth restriction"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for GitLab"
  type        = string
  default     = "t3.xlarge"
}

variable "data_volume_size" {
  description = "Size in GB for GitLab data EBS volume"
  type        = number
  default     = 100
}

variable "backup_replication_region" {
  description = "AWS region for backup cross-region replication"
  type        = string
  default     = "us-west-2"
}
```

**Step 4: Create main.tf (empty module composition — will wire modules as we build them)**

`terraform/main.tf`:
```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}

provider "aws" {
  alias  = "dns_account"
  region = var.aws_region

  assume_role {
    role_arn = var.dns_account_role_arn
  }

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "replication"
  region = var.backup_replication_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
```

**Step 5: Create outputs.tf (empty — will populate as modules are added)**

`terraform/outputs.tf`:
```hcl
# Outputs populated as modules are added
```

**Step 6: Validate**

Run: `cd terraform && terraform init -backend=false && terraform validate`
Expected: "Success! The configuration is valid."

**Step 7: Commit**

```bash
git add terraform/backend.tf terraform/variables.tf terraform/outputs.tf terraform/main.tf terraform/versions.tf
git commit -m "Add Terraform root configuration with providers and variables"
```

---

## Task 3: Networking Module — VPC, Subnets, NAT Gateway

**Files:**
- Create: `terraform/modules/networking/variables.tf`
- Create: `terraform/modules/networking/outputs.tf`
- Create: `terraform/modules/networking/vpc.tf`
- Modify: `terraform/main.tf` (add module call)

**Step 1: Create module variables**

`terraform/modules/networking/variables.tf`:
```hcl
variable "project_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "aws_region" {
  type = string
}
```

**Step 2: Create VPC, subnets, NAT Gateway, route tables**

`terraform/modules/networking/vpc.tf`:
```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public subnets (2 AZs for ALB requirement)
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.0.1.0/24, 10.0.2.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# Private subnets (2 AZs)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${data.aws_availability_zones.available.names[count.index]}"
  }
}

# NAT Gateway (single AZ to save cost)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```

**Step 3: Create module outputs**

`terraform/modules/networking/outputs.tf`:
```hcl
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
```

**Step 4: Wire into main.tf**

Add to `terraform/main.tf`:
```hcl
module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}
```

**Step 5: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 6: Commit**

```bash
git add terraform/modules/networking/ terraform/main.tf
git commit -m "Add networking module: VPC, subnets, NAT gateway"
```

---

## Task 4: Networking Module — VPC Flow Logs

**Files:**
- Create: `terraform/modules/networking/flow_logs.tf`

**Step 1: Create flow logs configuration**

`terraform/modules/networking/flow_logs.tf`:
```hcl
resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn
  max_aggregation_interval = 600

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_s3_bucket" "flow_logs" {
  bucket_prefix = "${var.project_name}-flow-logs-"

  tags = {
    Name = "${var.project_name}-flow-logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "archive"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/modules/networking/flow_logs.tf
git commit -m "Add VPC flow logs to S3 with lifecycle policy"
```

---

## Task 5: Networking Module — VPC Endpoints

**Files:**
- Create: `terraform/modules/networking/endpoints.tf`

**Step 1: Create VPC endpoints**

`terraform/modules/networking/endpoints.tf`:
```hcl
# S3 Gateway Endpoint (free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

# SSM Interface Endpoints (for Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

# Secrets Manager Interface Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

# CloudWatch Logs Interface Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-logs-endpoint"
  }
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpc-endpoints-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg"
  }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/modules/networking/endpoints.tf
git commit -m "Add VPC endpoints: S3, SSM, Secrets Manager, CloudWatch Logs"
```

---

## Task 6: Networking Module — Security Groups

**Files:**
- Create: `terraform/modules/networking/security_groups.tf`
- Modify: `terraform/modules/networking/outputs.tf` (add SG outputs)

**Step 1: Create security groups**

`terraform/modules/networking/security_groups.tf`:
```hcl
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC (Tailscale traffic)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "HTTP to GitLab"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.gitlab.id]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "gitlab" {
  name_prefix = "${var.project_name}-gitlab-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # ALB SG reference added via separate rule to avoid circular dependency
    cidr_blocks = [var.vpc_cidr]
  }

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
```

**Step 2: Add SG outputs to modules/networking/outputs.tf**

Append to `terraform/modules/networking/outputs.tf`:
```hcl
output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "gitlab_security_group_id" {
  value = aws_security_group.gitlab.id
}
```

**Step 3: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 4: Commit**

```bash
git add terraform/modules/networking/security_groups.tf terraform/modules/networking/outputs.tf
git commit -m "Add ALB and GitLab security groups"
```

---

## Task 7: Monitoring Module — CloudTrail

**Files:**
- Create: `terraform/modules/monitoring/variables.tf`
- Create: `terraform/modules/monitoring/outputs.tf`
- Create: `terraform/modules/monitoring/cloudtrail.tf`
- Modify: `terraform/main.tf` (add module call)

**Step 1: Create module variables and outputs**

`terraform/modules/monitoring/variables.tf`:
```hcl
variable "project_name" {
  type = string
}
```

`terraform/modules/monitoring/outputs.tf`:
```hcl
output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail.id
}
```

**Step 2: Create CloudTrail**

`terraform/modules/monitoring/cloudtrail.tf`:
```hcl
data "aws_caller_identity" "current" {}

resource "aws_cloudtrail" "main" {
  name                       = "${var.project_name}-trail"
  s3_bucket_name             = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail      = false
  enable_log_file_validation = true
  include_global_service_events = true

  tags = {
    Name = "${var.project_name}-cloudtrail"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket_prefix = "${var.project_name}-cloudtrail-"

  tags = {
    Name = "${var.project_name}-cloudtrail"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "archive"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}
```

**Step 3: Wire into main.tf**

Add to `terraform/main.tf`:
```hcl
module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
}
```

**Step 4: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add terraform/modules/monitoring/ terraform/main.tf
git commit -m "Add monitoring module with CloudTrail"
```

---

## Task 8: Monitoring Module — CloudWatch Alarms

**Files:**
- Create: `terraform/modules/monitoring/cloudwatch.tf`
- Modify: `terraform/modules/monitoring/variables.tf` (add instance_id var)

**Step 1: Add variable**

Append to `terraform/modules/monitoring/variables.tf`:
```hcl
variable "gitlab_instance_id" {
  description = "EC2 instance ID for CloudWatch alarms"
  type        = string
  default     = "" # Empty until EC2 module is wired
}
```

**Step 2: Create CloudWatch alarms**

`terraform/modules/monitoring/cloudwatch.tf`:
```hcl
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.gitlab_instance_id != "" ? 1 : 0

  alarm_name          = "${var.project_name}-gitlab-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "GitLab EC2 CPU > 90% for 15 minutes"

  dimensions = {
    InstanceId = var.gitlab_instance_id
  }

  tags = {
    Name = "${var.project_name}-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  count = var.gitlab_instance_id != "" ? 1 : 0

  alarm_name          = "${var.project_name}-gitlab-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "GitLab EC2 status check failed"

  dimensions = {
    InstanceId = var.gitlab_instance_id
  }

  tags = {
    Name = "${var.project_name}-status-check-alarm"
  }
}
```

**Step 3: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 4: Commit**

```bash
git add terraform/modules/monitoring/
git commit -m "Add CloudWatch alarms for CPU and status checks"
```

---

## Task 9: GitLab Module — IAM Role & Instance Profile

**Files:**
- Create: `terraform/modules/gitlab/variables.tf`
- Create: `terraform/modules/gitlab/outputs.tf`
- Create: `terraform/modules/gitlab/iam.tf`

**Step 1: Create module variables**

`terraform/modules/gitlab/variables.tf`:
```hcl
variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private subnet ID for the GitLab EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the GitLab EC2 instance"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.xlarge"
}

variable "data_volume_size" {
  type    = number
  default = 100
}

variable "domain_name" {
  type = string
}

variable "google_oauth_hd" {
  type = string
}

variable "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  type        = string
  default     = "" # Set after backup module creates the bucket
}
```

**Step 2: Create IAM role and instance profile**

`terraform/modules/gitlab/iam.tf`:
```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "gitlab" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

resource "aws_iam_instance_profile" "gitlab" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.gitlab.name
}

# SSM Session Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.gitlab.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Secrets Manager read access
resource "aws_iam_role_policy" "secrets" {
  name = "${var.project_name}-secrets-access"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"
      }
    ]
  })
}

# S3 backup access
resource "aws_iam_role_policy" "s3_backup" {
  name = "${var.project_name}-s3-backup"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-backups-*",
          "arn:aws:s3:::${var.project_name}-backups-*/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs
resource "aws_iam_role_policy" "cloudwatch" {
  name = "${var.project_name}-cloudwatch"
  role = aws_iam_role.gitlab.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/*"
      }
    ]
  })
}
```

**Step 3: Create module outputs**

`terraform/modules/gitlab/outputs.tf`:
```hcl
output "instance_id" {
  value = aws_instance.gitlab.id
}

output "instance_private_ip" {
  value = aws_instance.gitlab.private_ip
}

output "iam_role_arn" {
  value = aws_iam_role.gitlab.arn
}
```

**Step 4: Validate**

Run: `cd terraform && terraform validate`
Expected: Will have warnings about missing `aws_instance.gitlab` in outputs — expected, we'll create it next task.

**Step 5: Commit**

```bash
git add terraform/modules/gitlab/
git commit -m "Add GitLab IAM role with least-privilege policies"
```

---

## Task 10: GitLab Module — S3 Backup Bucket

**Files:**
- Create: `terraform/modules/gitlab/backup.tf`
- Modify: `terraform/modules/gitlab/outputs.tf` (add backup outputs)

**Step 1: Create backup bucket with cross-region replication**

`terraform/modules/gitlab/backup.tf`:
```hcl
resource "aws_s3_bucket" "backups" {
  bucket_prefix = "${var.project_name}-backups-"

  tags = {
    Name = "${var.project_name}-backups"
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "glacier-transition"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
```

**Step 2: Add backup bucket output**

Append to `terraform/modules/gitlab/outputs.tf`:
```hcl
output "backup_bucket_name" {
  value = aws_s3_bucket.backups.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backups.arn
}
```

**Step 3: Validate**

Run: `cd terraform && terraform validate`

**Step 4: Commit**

```bash
git add terraform/modules/gitlab/backup.tf terraform/modules/gitlab/outputs.tf
git commit -m "Add S3 backup bucket with versioning and Glacier lifecycle"
```

---

## Task 11: GitLab Module — Secrets Manager

**Files:**
- Create: `terraform/modules/gitlab/secrets.tf`

**Step 1: Create empty secrets (values populated manually)**

`terraform/modules/gitlab/secrets.tf`:
```hcl
resource "aws_secretsmanager_secret" "root_password" {
  name = "${var.project_name}/root-password"
  tags = { Name = "${var.project_name}-root-password" }
}

resource "aws_secretsmanager_secret" "oauth_client_id" {
  name = "${var.project_name}/oauth/client-id"
  tags = { Name = "${var.project_name}-oauth-client-id" }
}

resource "aws_secretsmanager_secret" "oauth_client_secret" {
  name = "${var.project_name}/oauth/client-secret"
  tags = { Name = "${var.project_name}-oauth-client-secret" }
}

resource "aws_secretsmanager_secret" "tailscale_auth_key" {
  name = "${var.project_name}/tailscale/auth-key"
  tags = { Name = "${var.project_name}-tailscale-auth-key" }
}

resource "aws_secretsmanager_secret" "gitlab_secrets_json" {
  name        = "${var.project_name}/secrets-json"
  description = "Backup of /etc/gitlab/gitlab-secrets.json"
  tags        = { Name = "${var.project_name}-secrets-json" }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`

**Step 3: Commit**

```bash
git add terraform/modules/gitlab/secrets.tf
git commit -m "Add Secrets Manager entries for GitLab credentials"
```

---

## Task 12: GitLab Module — User Data Script

**Files:**
- Create: `terraform/modules/gitlab/user_data.sh`

**Step 1: Create bootstrap script**

`terraform/modules/gitlab/user_data.sh`:
```bash
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/gitlab-bootstrap.log) 2>&1

echo "=== GitLab CE Bootstrap ==="
REGION="${region}"
PROJECT="${project_name}"
DOMAIN="${domain_name}"
OAUTH_HD="${google_oauth_hd}"

# Enable FIPS mode
fips-mode-setup --enable || echo "FIPS mode setup attempted"

# Install dependencies
dnf install -y curl policycoreutils openssh-server openssh-clients perl postfix jq

# Start and enable services
systemctl enable --now sshd
systemctl enable --now postfix

# Fetch secrets from Secrets Manager
get_secret() {
  aws secretsmanager get-secret-value \
    --secret-id "$1" \
    --region "$REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null || echo ""
}

ROOT_PASSWORD=$(get_secret "$PROJECT/root-password")
OAUTH_CLIENT_ID=$(get_secret "$PROJECT/oauth/client-id")
OAUTH_CLIENT_SECRET=$(get_secret "$PROJECT/oauth/client-secret")
TAILSCALE_AUTH_KEY=$(get_secret "$PROJECT/tailscale/auth-key")

# Format and mount data volume
DATA_DEVICE="/dev/nvme1n1"
if ! blkid "$DATA_DEVICE" > /dev/null 2>&1; then
  mkfs.xfs "$DATA_DEVICE"
fi
mkdir -p /var/opt/gitlab
mount "$DATA_DEVICE" /var/opt/gitlab
echo "$DATA_DEVICE /var/opt/gitlab xfs defaults,nofail 0 2" >> /etc/fstab

# Install GitLab CE
curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | bash
dnf install -y gitlab-ce

# Write gitlab.rb
cat > /etc/gitlab/gitlab.rb << 'GITLABCFG'
external_url 'https://${domain_name}'
nginx['listen_https'] = false
nginx['listen_port'] = 80

# Google OAuth
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['google_oauth2']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_auto_link_user'] = ['google_oauth2']

# Security hardening
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['password_authentication_enabled_for_web'] = true  # Enabled initially for root login
gitlab_rails['gravatar_enabled'] = false
gitlab_rails['default_projects_features_visibility_level'] = 'private'
gitlab_rails['default_project_visibility'] = 'private'
gitlab_rails['default_group_visibility'] = 'private'
gitlab_rails['default_snippet_visibility'] = 'private'

# Rate limiting
gitlab_rails['rate_limiting_enabled'] = true
gitlab_rails['throttle_authenticated_api_requests_per_period'] = 2000
gitlab_rails['throttle_authenticated_api_period_in_seconds'] = 3600

# Session management
gitlab_rails['session_expire_delay'] = 480

# Restrict outbound requests
gitlab_rails['allow_local_requests_from_web_hooks_and_services'] = false

# Backups to S3
gitlab_rails['backup_upload_connection'] = {
  'provider' => 'AWS',
  'region' => '${region}',
  'use_iam_profile' => true
}
gitlab_rails['backup_upload_remote_directory'] = '${backup_bucket}'
gitlab_rails['backup_keep_time'] = 604800

# Monitoring
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8']
GITLABCFG

# Inject OAuth credentials (avoid putting secrets in the heredoc)
if [ -n "$OAUTH_CLIENT_ID" ] && [ -n "$OAUTH_CLIENT_SECRET" ]; then
cat >> /etc/gitlab/gitlab.rb << OAUTHCFG
gitlab_rails['omniauth_providers'] = [
  {
    name: "google_oauth2",
    app_id: "$OAUTH_CLIENT_ID",
    app_secret: "$OAUTH_CLIENT_SECRET",
    args: { hd: "$OAUTH_HD", approval_prompt: "auto" }
  }
]
OAUTHCFG
fi

# Set initial root password
if [ -n "$ROOT_PASSWORD" ]; then
  export GITLAB_ROOT_PASSWORD="$ROOT_PASSWORD"
fi

# Reconfigure GitLab
gitlab-ctl reconfigure

# Set up daily backup cron
cat > /etc/cron.d/gitlab-backup << 'CRON'
0 2 * * * root /opt/gitlab/bin/gitlab-backup create STRATEGY=copy CRON=1
15 2 * * * root tar czf /var/opt/gitlab/backups/gitlab-config-$(date +\%Y\%m\%d).tar.gz /etc/gitlab/
CRON

# Install and configure Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
if [ -n "$TAILSCALE_AUTH_KEY" ]; then
  tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --advertise-tags=tag:gitlab --ssh
fi

# Install CloudWatch agent for disk monitoring
dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWAGENT'
{
  "metrics": {
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/", "/var/opt/gitlab"],
        "metrics_collection_interval": 300
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 300
      }
    }
  }
}
CWAGENT
systemctl enable --now amazon-cloudwatch-agent

echo "=== GitLab CE Bootstrap Complete ==="
```

**Step 2: Commit**

```bash
git add terraform/modules/gitlab/user_data.sh
git commit -m "Add GitLab EC2 user_data bootstrap script"
```

---

## Task 13: GitLab Module — EC2 Instance

**Files:**
- Create: `terraform/modules/gitlab/ec2.tf`

**Step 1: Create EC2 instance with data volume**

`terraform/modules/gitlab/ec2.tf`:
```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "gitlab" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.gitlab.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    region           = data.aws_region.current.name
    project_name     = var.project_name
    domain_name      = var.domain_name
    google_oauth_hd  = var.google_oauth_hd
    backup_bucket    = aws_s3_bucket.backups.id
  })

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-ec2"
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

  tags = {
    Name = "${var.project_name}-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.gitlab.id
}
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`

**Step 3: Commit**

```bash
git add terraform/modules/gitlab/ec2.tf
git commit -m "Add GitLab EC2 instance with encrypted data volume"
```

---

## Task 14: ALB Module

**Files:**
- Create: `terraform/modules/alb/variables.tf`
- Create: `terraform/modules/alb/outputs.tf`
- Create: `terraform/modules/alb/alb.tf`
- Create: `terraform/modules/alb/acm.tf`
- Create: `terraform/modules/alb/logging.tf`

**Step 1: Create module variables**

`terraform/modules/alb/variables.tf`:
```hcl
variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "route53_zone_id" {
  description = "Route 53 zone ID in DNS account for ACM validation"
  type        = string
}

variable "gitlab_instance_id" {
  type = string
}
```

**Step 2: Create ACM certificate**

`terraform/modules/alb/acm.tf`:
```hcl
resource "aws_acm_certificate" "gitlab" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

# DNS validation record created in DNS account
resource "aws_route53_record" "cert_validation" {
  provider = aws.dns_account

  for_each = {
    for dvo in aws_acm_certificate.gitlab.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "gitlab" {
  certificate_arn         = aws_acm_certificate.gitlab.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

**Step 3: Create ALB**

`terraform/modules/alb/alb.tf`:
```hcl
resource "aws_lb" "gitlab" {
  name               = "${var.project_name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "gitlab" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,302"
    path                = "/-/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 10
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "gitlab" {
  target_group_arn = aws_lb_target_group.gitlab.arn
  target_id        = var.gitlab_instance_id
  port             = 80
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.gitlab.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.gitlab.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab.arn
  }
}
```

**Step 4: Create ALB access logging**

`terraform/modules/alb/logging.tf`:
```hcl
data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket" "alb_logs" {
  bucket_prefix = "${var.project_name}-alb-logs-"

  tags = {
    Name = "${var.project_name}-alb-logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # ALB logs require AES256, not KMS
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "archive"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}
```

**Step 5: Create module outputs**

`terraform/modules/alb/outputs.tf`:
```hcl
output "alb_dns_name" {
  value = aws_lb.gitlab.dns_name
}

output "alb_zone_id" {
  value = aws_lb.gitlab.zone_id
}

output "alb_arn" {
  value = aws_lb.gitlab.arn
}
```

**Step 6: Validate**

Run: `cd terraform && terraform validate`
Note: The `aws.dns_account` provider reference in acm.tf requires the provider to be passed from the root module. This will be wired in the composition task.

**Step 7: Commit**

```bash
git add terraform/modules/alb/
git commit -m "Add ALB module with ACM cert, HTTPS listener, and access logging"
```

---

## Task 15: DNS Module

**Files:**
- Create: `terraform/modules/dns/variables.tf`
- Create: `terraform/modules/dns/outputs.tf`
- Create: `terraform/modules/dns/route53.tf`

**Step 1: Create module variables**

`terraform/modules/dns/variables.tf`:
```hcl
variable "project_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}
```

**Step 2: Create Route 53 private hosted zone**

`terraform/modules/dns/route53.tf`:
```hcl
# Extract the parent domain from the full domain name (e.g., yourcompany.com from gitlab.yourcompany.com)
locals {
  parent_domain = join(".", slice(split(".", var.domain_name), 1, length(split(".", var.domain_name))))
}

resource "aws_route53_zone" "private" {
  name = local.parent_domain

  vpc {
    vpc_id = var.vpc_id
  }

  tags = {
    Name = "${var.project_name}-private-zone"
  }
}

resource "aws_route53_record" "gitlab" {
  zone_id = aws_route53_zone.private.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
```

**Step 3: Create outputs**

`terraform/modules/dns/outputs.tf`:
```hcl
output "private_zone_id" {
  value = aws_route53_zone.private.zone_id
}
```

**Step 4: Validate**

Run: `cd terraform && terraform validate`

**Step 5: Commit**

```bash
git add terraform/modules/dns/
git commit -m "Add DNS module with Route 53 private hosted zone"
```

---

## Task 16: Wire All Modules Together in main.tf

**Files:**
- Modify: `terraform/main.tf` (complete module composition)
- Modify: `terraform/outputs.tf` (add useful outputs)

**Step 1: Update main.tf with all module calls**

Replace `terraform/main.tf` with:
```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = "production"
    }
  }
}

provider "aws" {
  alias  = "dns_account"
  region = var.aws_region

  assume_role {
    role_arn = var.dns_account_role_arn
  }

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

provider "aws" {
  alias  = "replication"
  region = var.backup_replication_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# --- Networking ---
module "networking" {
  source       = "./modules/networking"
  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

# --- Monitoring ---
module "monitoring" {
  source              = "./modules/monitoring"
  project_name        = var.project_name
  gitlab_instance_id  = module.gitlab.instance_id
}

# --- GitLab ---
module "gitlab" {
  source            = "./modules/gitlab"
  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.private_subnet_ids[0]
  security_group_id = module.networking.gitlab_security_group_id
  instance_type     = var.instance_type
  data_volume_size  = var.data_volume_size
  domain_name       = var.domain_name
  google_oauth_hd   = var.google_oauth_hd
}

# --- ALB ---
module "alb" {
  source              = "./modules/alb"
  project_name        = var.project_name
  vpc_id              = module.networking.vpc_id
  subnet_ids          = module.networking.private_subnet_ids
  security_group_id   = module.networking.alb_security_group_id
  domain_name         = var.domain_name
  route53_zone_id     = var.route53_zone_id
  gitlab_instance_id  = module.gitlab.instance_id

  providers = {
    aws             = aws
    aws.dns_account = aws.dns_account
  }
}

# --- DNS ---
module "dns" {
  source       = "./modules/dns"
  project_name = var.project_name
  domain_name  = var.domain_name
  vpc_id       = module.networking.vpc_id
  alb_dns_name = module.alb.alb_dns_name
  alb_zone_id  = module.alb.alb_zone_id
}
```

**Step 2: Update outputs.tf**

Replace `terraform/outputs.tf` with:
```hcl
output "gitlab_instance_id" {
  description = "GitLab EC2 instance ID"
  value       = module.gitlab.instance_id
}

output "gitlab_private_ip" {
  description = "GitLab EC2 private IP"
  value       = module.gitlab.instance_private_ip
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "gitlab_url" {
  description = "GitLab URL"
  value       = "https://${var.domain_name}"
}

output "backup_bucket" {
  description = "S3 backup bucket name"
  value       = module.gitlab.backup_bucket_name
}

output "ssm_connect_command" {
  description = "Command to connect via SSM"
  value       = "aws ssm start-session --target ${module.gitlab.instance_id}"
}
```

**Step 3: Add required_providers to ALB module for cross-account provider**

Create `terraform/modules/alb/versions.tf`:
```hcl
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.dns_account]
    }
  }
}
```

**Step 4: Validate**

Run: `cd terraform && terraform init -backend=false && terraform validate`
Expected: "Success! The configuration is valid."

**Step 5: Commit**

```bash
git add terraform/main.tf terraform/outputs.tf terraform/modules/alb/versions.tf
git commit -m "Wire all modules together in root main.tf"
```

---

## Task 17: Create terraform.tfvars.example

**Files:**
- Create: `terraform/terraform.tfvars.example`

**Step 1: Create example variables file**

`terraform/terraform.tfvars.example`:
```hcl
# Copy this to terraform.tfvars and fill in values
# terraform.tfvars is git-ignored

aws_region    = "us-east-1"
project_name  = "gitlab"
vpc_cidr      = "10.0.0.0/16"
instance_type = "t3.xlarge"

# Your GitLab domain
domain_name = "gitlab.yourcompany.com"

# Google Workspace domain for OAuth restriction
google_oauth_hd = "yourcompany.com"

# Cross-account DNS
dns_account_role_arn = "arn:aws:iam::ACCOUNT_ID:role/GitLabDNSAccess"
route53_zone_id      = "Z0123456789ABCDEFGHIJ"

# Backup
data_volume_size          = 100
backup_replication_region = "us-west-2"
```

**Step 2: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "Add terraform.tfvars.example with documented variables"
```

---

## Task 18: Deployment — Bootstrap State Backend

This is a manual step. Instructions for the operator:

**Step 1: Bootstrap**

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

**Step 2: Note outputs and update backend.tf**

Replace `ACCOUNT_ID` in `terraform/backend.tf` with the actual account ID from the output.

**Step 3: Initialize main Terraform**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with actual values
terraform init
```

**Step 4: Commit backend.tf update**

```bash
git add terraform/backend.tf
git commit -m "Update backend.tf with actual state bucket name"
```

---

## Task 19: Deployment — Populate Secrets & Apply

Manual steps for the operator:

**Step 1: Create Google OAuth credentials**

1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID (Web application type)
3. Set authorized redirect URI: `https://gitlab.yourcompany.com/users/auth/google_oauth2/callback`
4. Note the Client ID and Client Secret

**Step 2: Create Tailscale auth key**

1. Go to Tailscale Admin Console → Settings → Keys
2. Create a reusable auth key with tag `tag:gitlab`
3. Note the key

**Step 3: Generate root password**

```bash
openssl rand -base64 24
```

**Step 4: Populate Secrets Manager**

```bash
aws secretsmanager put-secret-value --secret-id gitlab/root-password --secret-string "YOUR_ROOT_PASSWORD"
aws secretsmanager put-secret-value --secret-id gitlab/oauth/client-id --secret-string "YOUR_CLIENT_ID"
aws secretsmanager put-secret-value --secret-id gitlab/oauth/client-secret --secret-string "YOUR_CLIENT_SECRET"
aws secretsmanager put-secret-value --secret-id gitlab/tailscale/auth-key --secret-string "tskey-auth-XXXXX"
```

Note: Run `terraform apply` first to create the secret resources, then populate values with the commands above, then either reboot the EC2 instance or run user_data manually via SSM.

**Step 5: Terraform apply**

```bash
cd terraform
terraform plan -out=plan.tfplan
# Review the plan carefully
terraform apply plan.tfplan
```

**Step 6: Verify**

```bash
# Check instance is running
aws ec2 describe-instances --filters "Name=tag:Name,Values=gitlab-ec2" --query 'Reservations[].Instances[].State.Name'

# Connect via SSM
aws ssm start-session --target INSTANCE_ID

# On the instance, check GitLab status
sudo gitlab-ctl status
```

---

## Task 20: Post-Deploy — Verify Google OAuth & Harden

Manual steps for the operator:

**Step 1: Connect via Tailscale and access GitLab**

1. Install Tailscale on your machine
2. Join the tailnet
3. Navigate to `https://gitlab.yourcompany.com`
4. Log in with root / password from Secrets Manager

**Step 2: Verify Google OAuth**

1. Log out
2. Click "Sign in with Google"
3. Authenticate with your Google Workspace account
4. Verify account is created and linked

**Step 3: Disable password auth (after OAuth is confirmed working)**

Via SSM on the instance:
```bash
sudo sed -i "s/password_authentication_enabled_for_web'] = true/password_authentication_enabled_for_web'] = false/" /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure
```

**Step 4: Back up gitlab-secrets.json**

```bash
sudo aws secretsmanager put-secret-value \
  --secret-id gitlab/secrets-json \
  --secret-string "$(sudo cat /etc/gitlab/gitlab-secrets.json)" \
  --region us-east-1
```

---

## Task 21: Verify Backup & Restore

Manual steps:

**Step 1: Run a manual backup**

```bash
sudo gitlab-backup create STRATEGY=copy
```

**Step 2: Verify backup uploaded to S3**

```bash
aws s3 ls s3://$(terraform output -raw backup_bucket)/ --recursive
```

**Step 3: Document restore procedure in a runbook (create later in quick-start)**

---

## Task 22: Documentation — quick-start.html

**Files:**
- Create: `docs/quick-start.html`

**Step 1: Create the developer onboarding guide**

`docs/quick-start.html` — a self-contained HTML page with sections:

1. **Prerequisites** — Tailscale account, Google Workspace account
2. **Install Tailscale** — links to download for macOS/Linux/Windows
3. **Connect to GitLab** — navigate to `https://gitlab.yourcompany.com`, sign in with Google
4. **Set up SSH key** — generate key, add to GitLab profile, configure `~/.ssh/config`
5. **Create a Personal Access Token** — step-by-step with screenshots placeholders
6. **Clone your first repo** — SSH and HTTPS examples
7. **Troubleshooting** — common issues (Tailscale not connected, OAuth redirect errors, SSH key format)

This is a content authoring task. Write the HTML with clean styling (no external dependencies). Include code blocks with copy buttons.

**Step 2: Commit**

```bash
git add docs/quick-start.html
git commit -m "Add developer quick-start onboarding guide"
```

---

## Task 23: Documentation — CMMC Level 2 Gap Analysis

**Files:**
- Create: `docs/cmmc-l2-gap-analysis.md`

**Step 1: Create gap analysis document**

Structure the document with all 14 CMMC Level 2 domains (mapping to NIST SP 800-171 r2):

| Domain | Practice Count |
|--------|---------------|
| Access Control (AC) | 22 |
| Awareness and Training (AT) | 3 |
| Audit and Accountability (AU) | 9 |
| Configuration Management (CM) | 9 |
| Identification and Authentication (IA) | 11 |
| Incident Response (IR) | 3 |
| Maintenance (MA) | 6 |
| Media Protection (MP) | 9 |
| Personnel Security (PS) | 2 |
| Physical Protection (PE) | 6 |
| Risk Assessment (RA) | 3 |
| Security Assessment (CA) | 4 |
| System and Communications Protection (SC) | 16 |
| System and Information Integrity (SI) | 7 |

For each practice:
- Practice ID and description
- Status: Implemented / Partially Implemented / Gap
- Evidence (reference specific Terraform files, gitlab.rb settings, AWS services)
- Remediation steps for gaps

**Step 2: Commit**

```bash
git add docs/cmmc-l2-gap-analysis.md
git commit -m "Add CMMC Level 2 gap analysis document"
```

---

## Task 24: Documentation — FedRAMP Moderate Gap Analysis

**Files:**
- Create: `docs/fedramp-moderate-gap-analysis.md`

**Step 1: Create gap analysis document**

Structure by NIST SP 800-53 Rev 5 control families at Moderate baseline. For each control:
- Control ID and title
- Status: Implemented / Partially Implemented / Gap / N/A
- Type: Infrastructure / Policy / Procedural
- Evidence (reference Terraform files, AWS services, gitlab.rb)
- Remediation steps

Key control families to cover:
- AC (Access Control)
- AU (Audit and Accountability)
- CA (Assessment, Authorization, and Monitoring)
- CM (Configuration Management)
- CP (Contingency Planning)
- IA (Identification and Authentication)
- IR (Incident Response)
- MA (Maintenance)
- MP (Media Protection)
- PE (Physical and Environmental Protection) — largely N/A (AWS responsibility)
- PL (Planning)
- PS (Personnel Security)
- RA (Risk Assessment)
- SA (System and Services Acquisition)
- SC (System and Communications Protection)
- SI (System and Information Integrity)
- SR (Supply Chain Risk Management)

For each, distinguish AWS shared responsibility (what AWS handles vs. what we handle).

**Step 2: Commit**

```bash
git add docs/fedramp-moderate-gap-analysis.md
git commit -m "Add FedRAMP Moderate gap analysis document"
```

---

## Summary

| Task | Description | Type |
|------|-------------|------|
| 1 | Project scaffolding + state backend bootstrap | Terraform |
| 2 | Root Terraform configuration | Terraform |
| 3 | Networking — VPC, subnets, NAT | Terraform |
| 4 | Networking — VPC Flow Logs | Terraform |
| 5 | Networking — VPC Endpoints | Terraform |
| 6 | Networking — Security Groups | Terraform |
| 7 | Monitoring — CloudTrail | Terraform |
| 8 | Monitoring — CloudWatch Alarms | Terraform |
| 9 | GitLab — IAM Role | Terraform |
| 10 | GitLab — S3 Backup Bucket | Terraform |
| 11 | GitLab — Secrets Manager | Terraform |
| 12 | GitLab — User Data Script | Shell |
| 13 | GitLab — EC2 Instance | Terraform |
| 14 | ALB — Cert, Listener, Logging | Terraform |
| 15 | DNS — Private Hosted Zone | Terraform |
| 16 | Wire all modules in main.tf | Terraform |
| 17 | terraform.tfvars.example | Config |
| 18 | Deploy — Bootstrap state backend | Manual |
| 19 | Deploy — Populate secrets & apply | Manual |
| 20 | Post-deploy — Verify OAuth & harden | Manual |
| 21 | Verify backup & restore | Manual |
| 22 | Documentation — quick-start.html | Docs |
| 23 | Documentation — CMMC L2 gap analysis | Docs |
| 24 | Documentation — FedRAMP Moderate gap analysis | Docs |
