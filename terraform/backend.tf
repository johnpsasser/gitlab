terraform {
  backend "s3" {
    bucket         = "gitlab-terraform-state-ACCOUNT_ID" # Update after bootstrap
    key            = "gitlab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitlab-terraform-locks"
    encrypt        = true
  }
}
