terraform {
  backend "s3" {
    # IMPORTANT: Replace ACCOUNT_ID with your 12-digit AWS account ID.
    # Run the bootstrap module first: cd bootstrap && terraform init && terraform apply
    # Find your account ID: aws sts get-caller-identity --query Account --output text
    #
    # Example: If account ID is 123456789012, the bucket name is:
    #   gitlab-terraform-state-123456789012
    bucket         = "gitlab-terraform-state-ACCOUNT_ID" # <-- REPLACE ACCOUNT_ID
    key            = "gitlab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitlab-terraform-locks"
    encrypt        = true
  }
}
