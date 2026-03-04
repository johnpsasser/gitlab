terraform {
  backend "s3" {
    # IMPORTANT: Replace ACCOUNT_ID with your 12-digit AWS account ID.
    # Run the bootstrap module first (terraform/bootstrap/) to create this bucket.
    # Find your account ID: aws sts get-caller-identity --query Account --output text
    bucket         = "gitlab-terraform-state-ACCOUNT_ID" # Update after bootstrap
    key            = "gitlab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitlab-terraform-locks"
    encrypt        = true
  }
}
