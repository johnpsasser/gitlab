resource "aws_secretsmanager_secret" "root_password" {
  #checkov:skip=CKV2_AWS_57:Rotation configured in modules/rotation -- checkov cannot resolve cross-module references
  name       = "${var.project_name}/root-password"
  kms_key_id = var.kms_key_id
  tags       = { Name = "${var.project_name}-root-password" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret" "gitlab_secrets_json" {
  #checkov:skip=CKV2_AWS_57:Secrets rotation requires Lambda -- tracked as TODO (IL2 IA-5(1))
  # Note: gitlab-secrets.json rotation is a manual procedure documented in
  # docs/quick-start.html. Automated rotation is not recommended because
  # changing the Rails secret_key_base invalidates all user sessions.
  name        = "${var.project_name}/secrets-json"
  description = "Backup of /etc/gitlab/gitlab-secrets.json"
  kms_key_id  = var.kms_key_id
  tags        = { Name = "${var.project_name}-secrets-json" }

  lifecycle {
    prevent_destroy = true
  }
}
