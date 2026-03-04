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


# Wait for EBS data volume to attach
DATA_DEVICE="/dev/nvme1n1"
echo "Waiting for data volume $DATA_DEVICE to be available..."
ATTEMPTS=0
MAX_ATTEMPTS=60
while [ ! -b "$DATA_DEVICE" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  sleep 5
  ATTEMPTS=$((ATTEMPTS + 1))
  echo "  Waiting for $DATA_DEVICE... attempt $ATTEMPTS/$MAX_ATTEMPTS"
done

if [ ! -b "$DATA_DEVICE" ]; then
  echo "ERROR: Data volume $DATA_DEVICE did not appear after $((MAX_ATTEMPTS * 5)) seconds"
  exit 1
fi

# Format and mount data volume
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
