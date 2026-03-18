#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/gitlab-bootstrap.log) 2>&1

echo "=== GitLab CE Bootstrap ==="
REGION="${region}"
PROJECT="${project_name}"
DOMAIN="${domain_name}"

# FIPS mode: use a FIPS-validated AMI (al2023-ami-*-fips-*) for IL2 compliance

# Install dependencies
dnf install -y curl policycoreutils perl postfix jq

# Start and enable services
systemctl enable --now postfix

# Disable and remove SSH daemon (AC-17, CM-7)
# All access is via SSM Session Manager -- SSH is not needed
systemctl stop sshd 2>/dev/null || true
systemctl disable sshd 2>/dev/null || true
dnf remove -y openssh-server 2>/dev/null || true

# Fetch secrets from Secrets Manager
get_secret() {
  aws secretsmanager get-secret-value \
    --secret-id "$1" \
    --region "$REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null || echo ""
}

ROOT_PASSWORD=$(get_secret "$PROJECT/root-password")


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
# NOTE: curl-pipe-bash is an accepted supply chain risk for this deployment.
# Mitigation: HTTPS-only, GitLab's official repo, VPC egress restricted.
# For higher assurance, consider pre-baking a golden AMI with GitLab installed.
curl -sS https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | bash
dnf install -y gitlab-ce

# Generate self-signed certificate for internal ALB-to-EC2 TLS (SC-8)
mkdir -p /etc/gitlab/ssl
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=US/ST=Virginia/L=Arlington/O=$PROJECT/CN=$DOMAIN" \
  -keyout "/etc/gitlab/ssl/$DOMAIN.key" \
  -out "/etc/gitlab/ssl/$DOMAIN.crt"
chmod 600 "/etc/gitlab/ssl/$DOMAIN.key"

# Write gitlab.rb
cat > /etc/gitlab/gitlab.rb << 'GITLABCFG'
external_url 'https://${domain_name}'
nginx['listen_https'] = true
nginx['listen_port'] = 443
nginx['ssl_certificate'] = "/etc/gitlab/ssl/${domain_name}.crt"
nginx['ssl_certificate_key'] = "/etc/gitlab/ssl/${domain_name}.key"
nginx['redirect_http_to_https'] = false

# Security hardening (IA-2, IA-5)
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['password_authentication_enabled_for_web'] = true  # GitLab native authentication for IL2 compliance
gitlab_rails['password_minimum_length'] = 15
gitlab_rails['require_two_factor_authentication'] = true         # IA-2(1): MFA for all users
gitlab_rails['two_factor_authentication_grace_period'] = 0       # No grace period -- enforce immediately
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
gitlab_rails['session_expire_delay'] = 60

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

# DoD consent banner (AC-8)
gitlab_rails['extra_sign_in_text'] = <<~BANNER
  **NOTICE**: You are accessing a U.S. Government (USG) Information System (IS) that is provided for USG-authorized use only. By using this IS (which includes any device attached to this IS), you consent to the following conditions:

  - The USG routinely intercepts and monitors communications on this IS for purposes including, but not limited to, penetration testing, COMSEC monitoring, network operations and defense, personnel misconduct (PM), law enforcement (LE), and counterintelligence (CI) investigations.
  - At any time, the USG may inspect and seize data stored on this IS.
  - Communications using, or data stored on, this IS are not private, are subject to routine monitoring, interception, and search, and may be disclosed or used for any USG-authorized purpose.
  - This IS includes security measures (e.g., authentication and access controls) to protect USG interests -- not for your personal benefit or privacy.
  - Notwithstanding the above, using this IS does not constitute consent to PM, LE, or CI investigative searching or monitoring of the content of privileged communications, or work product, related to personal representation or services by attorneys, psychotherapists, or clergy, and their assistants. Such communications and work product are private and confidential. See User Agreement for details.
BANNER

# Monitoring
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8']
GITLABCFG

# Set initial root password
if [ -n "$ROOT_PASSWORD" ]; then
  export GITLAB_ROOT_PASSWORD="$ROOT_PASSWORD"
fi

# Reconfigure GitLab
gitlab-ctl reconfigure

# Set up daily backup cron
cat > /etc/cron.d/gitlab-backup << 'CRON'
0 2 * * * root /opt/gitlab/bin/gitlab-backup create STRATEGY=copy CRON=1
15 2 * * * root tar czf /var/opt/gitlab/backups/gitlab-config-$(date +\%Y\%m\%d).tar.gz /etc/gitlab/ && aws s3 cp /var/opt/gitlab/backups/gitlab-config-$(date +\%Y\%m\%d).tar.gz s3://${backup_bucket}/config-backups/ --region ${region}
CRON

# Install CloudWatch agent for disk monitoring
dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWAGENTCONFIG'
${cloudwatch_agent_config}
CWAGENTCONFIG
systemctl enable --now amazon-cloudwatch-agent

# === ClamAV Antimalware (SI-3) ===
echo "=== Installing ClamAV ==="
dnf install -y clamav clamav-update clamd

# Configure freshclam for daily signature updates
cat > /etc/freshclam.conf << 'FRESHCLAM'
DatabaseDirectory /var/lib/clamav
UpdateLogFile /var/log/clamav/freshclam.log
LogTime yes
DatabaseMirror database.clamav.net
MaxAttempts 3
ScriptedUpdates yes
NotifyClamd /etc/clamd.d/scan.conf
FRESHCLAM

# Configure clamd
cat > /etc/clamd.d/scan.conf << 'CLAMD'
LocalSocket /run/clamd.scan/clamd.sock
LogFile /var/log/clamav/clamd.log
LogTime yes
DatabaseDirectory /var/lib/clamav
CLAMD

# Create log directory
mkdir -p /var/log/clamav
chown clamscan:clamscan /var/log/clamav

# Run initial signature update
freshclam

# Enable and start clamd
systemctl enable --now clamd@scan

# Daily scan cron job targeting GitLab data directories
cat > /etc/cron.d/clamav-scan << 'CLAMCRON'
0 3 * * * root /usr/bin/clamscan --recursive --infected --log=/var/log/clamav/scan.log /var/opt/gitlab/git-data/ /var/opt/gitlab/uploads/ 2>&1
CLAMCRON

# Daily signature update cron
cat > /etc/cron.d/clamav-update << 'CLAMUPDATECRON'
0 1 * * * root /usr/bin/freshclam --quiet 2>&1
CLAMUPDATECRON

# Add ClamAV logs to CloudWatch Agent config
cat > /opt/aws/amazon-cloudwatch-agent/etc/clamav-logs.json << 'CWCLAMAV'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/clamav/scan.log",
            "log_group_name": "/${project_name}/clamav/scan",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/clamav/clamd.log",
            "log_group_name": "/${project_name}/clamav/clamd",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCLAMAV

# Merge ClamAV log config into CloudWatch Agent and restart
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a append-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/clamav-logs.json

# === AIDE File Integrity Monitoring (SI-7) ===
echo "=== Installing AIDE ==="
dnf install -y aide

# Initialize AIDE database
aide --init
mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

# Daily AIDE check cron job
cat > /etc/cron.d/aide-check << 'AIDECRON'
0 4 * * * root /usr/sbin/aide --check >> /var/log/aide/aide-check.log 2>&1
AIDECRON

# Create log directory
mkdir -p /var/log/aide

# Add AIDE logs to CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/aide-logs.json << 'CWAIDE'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/aide/aide-check.log",
            "log_group_name": "/${project_name}/aide/check",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWAIDE

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a append-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/aide-logs.json

echo "=== GitLab CE Bootstrap Complete ==="
