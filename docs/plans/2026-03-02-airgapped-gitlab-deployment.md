# Air-Gapped GitLab CE on AWS — Deployment Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the validated Terraform infrastructure to AWS and bring GitLab CE online with Google OAuth authentication and Tailscale VPN access.

**Prerequisites:**
- Implementation plan complete (`docs/plans/2026-03-02-airgapped-gitlab-plan.md`)
- All Terraform code written and validated
- Checkov scan passed (no HIGH/CRITICAL findings)
- `terraform plan` verified successfully
- AWS credentials configured with sufficient permissions

**Design doc:** `docs/plans/2026-03-02-airgapped-gitlab-design.md`

---

## Task 1: Bootstrap Terraform State Backend

**Step 1: Apply bootstrap configuration**

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Expected: S3 bucket and DynamoDB table created.

**Step 2: Note the outputs**

```bash
terraform output state_bucket
terraform output lock_table
```

**Step 3: Update backend.tf with actual values**

Replace `ACCOUNT_ID` in `terraform/backend.tf` with the actual account ID from the state bucket name.

**Step 4: Commit**

```bash
git add terraform/backend.tf
git commit -m "Update backend.tf with actual state bucket name"
```

---

## Task 2: Create Google OAuth Credentials

**Step 1: Open Google Cloud Console**

Navigate to: APIs & Services → Credentials

**Step 2: Create OAuth 2.0 Client ID**

- Application type: Web application
- Name: GitLab
- Authorized redirect URIs: `https://gitlab.yourcompany.com/users/auth/google_oauth2/callback`

**Step 3: Note the Client ID and Client Secret**

Save these securely — you'll need them in Task 5.

---

## Task 3: Create Tailscale Auth Key

**Step 1: Open Tailscale Admin Console**

Navigate to: Settings → Keys

**Step 2: Generate auth key**

- Type: Reusable
- Tags: `tag:gitlab`
- Expiry: 90 days (or your preference)

**Step 3: Note the key**

Format: `tskey-auth-XXXXX`. Save securely — needed in Task 5.

---

## Task 4: Initialize Terraform with Remote Backend

**Step 1: Create terraform.tfvars**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your actual values:
- `domain_name` — your GitLab domain
- `google_oauth_hd` — your Google Workspace domain
- `dns_account_role_arn` — IAM role ARN in your DNS account
- `route53_zone_id` — hosted zone ID in DNS account

**Step 2: Initialize with remote backend**

```bash
terraform init
```

Expected: "Successfully configured the backend 'S3'!"

**Step 3: Verify plan**

```bash
terraform plan -out=plan.tfplan
```

Review the plan. Should match what you saw during implementation verification.

---

## Task 5: Populate Secrets Manager

Note: Terraform must be applied first (Task 6) to create the secret resources. This task runs immediately after the initial apply.

**Step 1: Generate root password**

```bash
openssl rand -base64 24
```

**Step 2: Populate all secrets**

```bash
aws secretsmanager put-secret-value \
  --secret-id gitlab/root-password \
  --secret-string "YOUR_GENERATED_ROOT_PASSWORD"

aws secretsmanager put-secret-value \
  --secret-id gitlab/oauth/client-id \
  --secret-string "YOUR_GOOGLE_CLIENT_ID"

aws secretsmanager put-secret-value \
  --secret-id gitlab/oauth/client-secret \
  --secret-string "YOUR_GOOGLE_CLIENT_SECRET"

aws secretsmanager put-secret-value \
  --secret-id gitlab/tailscale/auth-key \
  --secret-string "tskey-auth-XXXXX"
```

---

## Task 6: Terraform Apply

**Step 1: Apply infrastructure**

```bash
cd terraform
terraform apply plan.tfplan
```

If the plan has expired, re-run:
```bash
terraform plan -out=plan.tfplan && terraform apply plan.tfplan
```

Expected: All resources created successfully.

**Step 2: Note key outputs**

```bash
terraform output gitlab_instance_id
terraform output gitlab_private_ip
terraform output alb_dns_name
terraform output gitlab_url
terraform output ssm_connect_command
```

**Step 3: Wait for EC2 bootstrap to complete**

The user_data script takes ~10-15 minutes to install GitLab. Monitor via SSM:

```bash
aws ssm start-session --target $(terraform output -raw gitlab_instance_id)
```

On the instance:
```bash
sudo tail -f /var/log/gitlab-bootstrap.log
```

Wait for: `=== GitLab CE Bootstrap Complete ===`

---

## Task 7: Populate Secrets and Reboot

Since secrets were empty during first boot, the EC2 instance needs to re-run its bootstrap with actual secret values.

**Step 1: Populate secrets** (if not already done in Task 5)

**Step 2: Reboot instance to re-run user_data**

```bash
aws ec2 reboot-instances --instance-ids $(terraform output -raw gitlab_instance_id)
```

**Step 3: Wait for GitLab to come up**

```bash
aws ssm start-session --target $(terraform output -raw gitlab_instance_id)
sudo tail -f /var/log/gitlab-bootstrap.log
sudo gitlab-ctl status
```

Expected: All GitLab services running (puma, sidekiq, gitaly, postgresql, redis, etc.)

---

## Task 8: Verify Tailscale Connectivity

**Step 1: Check Tailscale status on GitLab instance**

Via SSM:
```bash
sudo tailscale status
```

Expected: Shows the machine connected to your tailnet with `tag:gitlab`.

**Step 2: From your local machine, verify connectivity**

```bash
# Ping GitLab via Tailscale IP
ping <tailscale-ip-of-gitlab>

# Test HTTPS via ALB
curl -k https://gitlab.yourcompany.com/-/health
```

Expected: `GitLab OK` response.

---

## Task 9: Verify Google OAuth Login

**Step 1: Log in with root account**

1. Navigate to `https://gitlab.yourcompany.com`
2. Log in with username `root` and the password from Secrets Manager
3. Verify the admin dashboard loads

**Step 2: Test Google OAuth**

1. Log out
2. Click "Sign in with Google"
3. Authenticate with your Google Workspace account
4. Verify account is created and linked
5. Verify you can access the dashboard

**Step 3: Verify domain restriction**

1. Attempt login with a personal Gmail account (not your Workspace domain)
2. Expected: Login denied (the `hd` parameter restricts to your domain)

---

## Task 10: Harden — Disable Password Authentication

Only do this after confirming Google OAuth works in Task 9.

**Step 1: Update gitlab.rb via SSM**

```bash
aws ssm start-session --target $(terraform output -raw gitlab_instance_id)
```

On the instance:
```bash
sudo sed -i "s/password_authentication_enabled_for_web'] = true/password_authentication_enabled_for_web'] = false/" /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure
```

**Step 2: Verify password login is disabled**

1. Navigate to GitLab login page
2. Confirm "Sign in with Google" is the only option (no username/password form for non-root users)
3. Root can still log in with password via `/users/sign_in` as an emergency override

---

## Task 11: Back Up gitlab-secrets.json

**Step 1: Upload to Secrets Manager**

Via SSM:
```bash
sudo aws secretsmanager put-secret-value \
  --secret-id gitlab/secrets-json \
  --secret-string "$(sudo cat /etc/gitlab/gitlab-secrets.json)" \
  --region us-east-1
```

This file contains encryption keys for the database. Without it, backups cannot be restored.

---

## Task 12: Verify Backup & Restore

**Step 1: Run a manual backup**

Via SSM:
```bash
sudo gitlab-backup create STRATEGY=copy
```

**Step 2: Verify backup uploaded to S3**

```bash
aws s3 ls s3://$(terraform output -raw backup_bucket)/ --recursive
```

Expected: A tar file with today's date.

**Step 3: Verify cron is configured**

Via SSM:
```bash
cat /etc/cron.d/gitlab-backup
```

Expected: Daily backup at 2:00 AM and config backup at 2:15 AM.

---

## Task 13: Configure Tailscale ACLs

**Step 1: Open Tailscale Admin Console**

Navigate to: Access Controls

**Step 2: Apply ACL policy**

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["group:engineers"],
      "dst": ["tag:gitlab:443", "tag:gitlab:22"]
    },
    {
      "action": "accept",
      "src": ["group:admins"],
      "dst": ["tag:gitlab:*"]
    }
  ],
  "groups": {
    "group:engineers": ["autogroup:member"],
    "group:admins":    ["admin@yourcompany.com"]
  },
  "tagOwners": {
    "tag:gitlab": ["group:admins"]
  }
}
```

**Step 3: Test ACL enforcement**

From a non-admin Tailscale machine, verify you can reach `:443` and `:22` but not other ports.

---

## Task 14: Smoke Test All Access Patterns

**Step 1: Web UI via Tailscale**

1. Navigate to `https://gitlab.yourcompany.com`
2. Sign in with Google OAuth
3. Create a test project

**Step 2: Git clone via SSH**

```bash
# Add SSH key to GitLab profile first
ssh-keygen -t ed25519 -C "your@email.com"  # if needed
# Paste public key into GitLab → Preferences → SSH Keys

git clone git@<tailscale-ip>:root/test-project.git
cd test-project
echo "test" > README.md
git add . && git commit -m "test" && git push
```

**Step 3: Git clone via HTTPS + PAT**

1. Create a PAT in GitLab → Preferences → Access Tokens (scopes: `read_repository`, `write_repository`)
2. Clone:
```bash
git clone https://oauth2:YOUR_PAT@gitlab.yourcompany.com/root/test-project.git
```

**Step 4: Admin access via SSM**

```bash
aws ssm start-session --target $(terraform output -raw gitlab_instance_id)
sudo gitlab-ctl status
sudo gitlab-rake gitlab:check
```

Expected: All checks pass.

**Step 5: Verify CloudWatch alarms exist**

```bash
aws cloudwatch describe-alarms --alarm-name-prefix gitlab
```

Expected: CPU and status check alarms listed.

---

## Task 15: Clean Up Test Data

**Step 1: Delete test project**

In GitLab UI: test-project → Settings → General → Advanced → Delete project

**Step 2: Document completion**

Record the deployment date and any deviations from the plan for your records.

---

## Summary

| Task | Description | Type |
|------|-------------|------|
| 1 | Bootstrap Terraform state backend | Infra |
| 2 | Create Google OAuth credentials | Manual |
| 3 | Create Tailscale auth key | Manual |
| 4 | Initialize Terraform with remote backend | Infra |
| 5 | Populate Secrets Manager | Manual |
| 6 | Terraform apply | Infra |
| 7 | Populate secrets and reboot | Manual |
| 8 | Verify Tailscale connectivity | Verify |
| 9 | Verify Google OAuth login | Verify |
| 10 | Harden — disable password auth | Config |
| 11 | Back up gitlab-secrets.json | Ops |
| 12 | Verify backup & restore | Verify |
| 13 | Configure Tailscale ACLs | Config |
| 14 | Smoke test all access patterns | Verify |
| 15 | Clean up test data | Cleanup |
