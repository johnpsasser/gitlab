resource "aws_secretsmanager_secret" "root_password" {
  # TODO: Implement Lambda-based rotation (IL2 IA-5(1))
  name       = "${var.project_name}/root-password"
  kms_key_id = var.kms_key_id
  tags       = { Name = "${var.project_name}-root-password" }
}

resource "aws_secretsmanager_secret" "gitlab_secrets_json" {
  # TODO: Implement Lambda-based rotation (IL2 IA-5(1))
  name        = "${var.project_name}/secrets-json"
  description = "Backup of /etc/gitlab/gitlab-secrets.json"
  kms_key_id  = var.kms_key_id
  tags        = { Name = "${var.project_name}-secrets-json" }
}
