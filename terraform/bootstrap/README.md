# Terraform State Bootstrap

One-time setup to create the S3 bucket and DynamoDB table for Terraform remote state.

## Prerequisites

- AWS CLI configured with credentials that have S3 and DynamoDB admin permissions
- Terraform >= 1.5

## Usage

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

## After Bootstrap

1. Get your AWS account ID:
   ```bash
   aws sts get-caller-identity --query Account --output text
   ```

2. Edit `terraform/backend.tf` and replace `ACCOUNT_ID` with your 12-digit account ID:
   ```
   bucket = "gitlab-terraform-state-123456789012"
   ```

3. Initialize the main module:
   ```bash
   cd terraform
   terraform init
   ```

## Resources Created

- S3 bucket: `gitlab-terraform-state-<account-id>` (versioning, encryption, public access blocked)
- DynamoDB table: `gitlab-terraform-locks` (state locking)
