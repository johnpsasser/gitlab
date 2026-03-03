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
