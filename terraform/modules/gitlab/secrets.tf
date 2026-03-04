resource "aws_secretsmanager_secret" "root_password" {
  #checkov:skip=CKV_AWS_149:Secrets Manager KMS CMK — default aws/secretsmanager key is sufficient
  #checkov:skip=CKV2_AWS_57:Secrets rotation requires Lambda — managed operationally, not via Terraform
  name = "${var.project_name}/root-password"
  tags = { Name = "${var.project_name}-root-password" }
}

resource "aws_secretsmanager_secret" "oauth_client_id" {
  #checkov:skip=CKV_AWS_149:Secrets Manager KMS CMK — default aws/secretsmanager key is sufficient
  #checkov:skip=CKV2_AWS_57:Secrets rotation requires Lambda — managed operationally, not via Terraform
  name = "${var.project_name}/oauth/client-id"
  tags = { Name = "${var.project_name}-oauth-client-id" }
}

resource "aws_secretsmanager_secret" "oauth_client_secret" {
  #checkov:skip=CKV_AWS_149:Secrets Manager KMS CMK — default aws/secretsmanager key is sufficient
  #checkov:skip=CKV2_AWS_57:Secrets rotation requires Lambda — managed operationally, not via Terraform
  name = "${var.project_name}/oauth/client-secret"
  tags = { Name = "${var.project_name}-oauth-client-secret" }
}

resource "aws_secretsmanager_secret" "gitlab_secrets_json" {
  #checkov:skip=CKV_AWS_149:Secrets Manager KMS CMK — default aws/secretsmanager key is sufficient
  #checkov:skip=CKV2_AWS_57:Secrets rotation requires Lambda — managed operationally, not via Terraform
  name        = "${var.project_name}/secrets-json"
  description = "Backup of /etc/gitlab/gitlab-secrets.json"
  tags        = { Name = "${var.project_name}-secrets-json" }
}
