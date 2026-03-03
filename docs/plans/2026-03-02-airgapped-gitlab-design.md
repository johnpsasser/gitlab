# Air-Gapped GitLab CE on AWS — Design Document

**Date:** 2026-03-02
**Status:** Approved

## Summary

Deploy GitLab Community Edition on AWS EC2 in a private subnet with no public internet exposure. Access via Tailscale VPN, authentication via Google OAuth, infrastructure managed entirely by Terraform. Architecture makes compliance-informed choices (FIPS, CloudTrail, encryption, audit logging) to avoid rework if pursuing CMMC Level 2 or FedRAMP Moderate later.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Edition | GitLab CE | Free, sufficient for 1-10 users, SAML/OAuth supported |
| Deployment | Omnibus direct install on EC2 | Production-recommended, simpler ops than Docker, better compliance story |
| Instance | t3.xlarge (4 vCPU, 16 GB RAM) | Comfortable headroom for 10 users |
| OS | Amazon Linux 2023 (FIPS mode) | FIPS 140-2 crypto for compliance readiness |
| Network | Private subnet, internal ALB, NAT GW | No public exposure; NAT for outbound updates only |
| Access | Tailscale VPN + SSM Session Manager | Identity-aware access + auditable admin shell |
| Auth | Google OAuth via OmniAuth | Simpler than SAML, same security controls |
| Deprovisioning | Manual | Sufficient for small team; automate later |
| IaC | Terraform, modular layout | Greenfield account, clean module structure |
| Secrets | AWS Secrets Manager | No secrets in Terraform state or git |
| DNS | Route 53 private hosted zone | Cross-account cert validation for ACM |
| Backups | Daily to S3, cross-region replication | 7-day local retention, Glacier after 30 days |
| Region | us-east-1 | Best service availability, lowest cost |

## Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  VPC: 10.0.0.0/16                                           │
│                                                             │
│  ┌──────────────────────┐   ┌──────────────────────┐        │
│  │ Public Subnet A      │   │ Public Subnet B      │        │
│  │ 10.0.1.0/24          │   │ 10.0.2.0/24          │        │
│  │  ┌────────────────┐  │   │                      │        │
│  │  │ NAT Gateway    │  │   │                      │        │
│  │  └────────────────┘  │   │                      │        │
│  └──────────────────────┘   └──────────────────────┘        │
│           │                          │                      │
│  ┌────────┴─────────────────────────┴───────────────┐       │
│  │              ALB (internal)                       │       │
│  │              HTTPS :443                           │       │
│  └────────┬─────────────────────────────────────────┘       │
│           │                                                 │
│  ┌────────┴─────────────┐   ┌──────────────────────┐        │
│  │ Private Subnet A     │   │ Private Subnet B     │        │
│  │ 10.0.10.0/24         │   │ 10.0.11.0/24         │        │
│  │  ┌────────────────┐  │   │                      │        │
│  │  │ GitLab EC2     │  │   │                      │        │
│  │  │ t3.xlarge      │  │   │                      │        │
│  │  │ + Tailscale    │  │   │                      │        │
│  │  └────────────────┘  │   │                      │        │
│  └──────────────────────┘   └──────────────────────┘        │
│                                                             │
│  ┌──────────────────────────────────────────────────┐       │
│  │ VPC Endpoints: S3, SSM, CloudWatch Logs,         │       │
│  │ Secrets Manager                                   │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘

External Access:
  Developer laptop → Tailscale → ALB → GitLab (HTTPS)
  Developer laptop → Tailscale → GitLab :22 (SSH/Git)
  Admin → SSM Session Manager → GitLab EC2 (no SSH keys)
```

- **Internal ALB** — not internet-facing, only reachable via Tailscale network
- **NAT Gateway** — single AZ to save cost (~$32/mo + data), outbound only
- **VPC Endpoints** — S3, SSM, CloudWatch Logs, Secrets Manager (keeps traffic off public internet)
- **SSM Session Manager** — admin access with full audit trail, no SSH keys
- **Two AZs** for ALB (required) but GitLab runs in one AZ (no HA at this scale)

## EC2 Instance & GitLab Configuration

### Instance

- AMI: Amazon Linux 2023, FIPS mode enabled
- Root volume: 50 GB gp3, encrypted (KMS)
- Data volume: 100 GB gp3, encrypted (KMS), mounted at `/var/opt/gitlab`
- IAM Instance Profile: S3, SSM, CloudWatch, Secrets Manager

### gitlab.rb

```ruby
# External URL (ALB handles TLS termination)
external_url 'https://gitlab.yourcompany.com'
nginx['listen_https'] = false
nginx['listen_port'] = 80

# Google OAuth via OmniAuth
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['google_oauth2']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_auto_link_user'] = ['google_oauth2']

gitlab_rails['omniauth_providers'] = [
  {
    name: "google_oauth2",
    app_id: "GOOGLE_CLIENT_ID",
    app_secret: "GOOGLE_CLIENT_SECRET",
    args: { hd: "yourcompany.com", approval_prompt: "auto" }
  }
]

# Security hardening
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['password_authentication_enabled_for_web'] = false
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
gitlab_rails['session_expire_delay'] = 480  # 8 hours

# Restrict outbound requests
gitlab_rails['allow_local_requests_from_web_hooks_and_services'] = false

# Backups to S3
gitlab_rails['backup_upload_connection'] = {
  provider: "AWS",
  region: "us-east-1",
  use_iam_profile: true
}
gitlab_rails['backup_upload_remote_directory'] = 'your-gitlab-backups-bucket'
gitlab_rails['backup_keep_time'] = 604800  # 7 days local

# Monitoring
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8']
```

### Bootstrap Sequence

1. Terraform creates infrastructure + EC2 with user_data script
2. user_data installs GitLab CE, pulls secrets from Secrets Manager, writes gitlab.rb
3. `gitlab-ctl reconfigure` runs
4. Initial root password set from Secrets Manager
5. Admin logs in with root password, verifies Google OAuth
6. Admin disables password auth (already in gitlab.rb, but verify)
7. Root password becomes emergency-only (stored in Secrets Manager)

### Backup Strategy

- `gitlab-backup create` via cron daily, uploads to S3
- `/etc/gitlab/` and `/etc/gitlab/gitlab-secrets.json` backed up separately to S3
- S3 bucket: versioned, lifecycle to Glacier after 30 days
- Cross-region replication to us-west-2

## Tailscale Integration & Access Model

### Access Patterns

| Action | Path | Auth |
|--------|------|------|
| Web UI | `https://gitlab.yourcompany.com` → Tailscale → ALB → GitLab | Google OAuth |
| Git SSH | `git@<tailscale-ip>:group/repo.git` → Tailscale → GitLab :22 | SSH key |
| Git HTTPS | `https://gitlab.yourcompany.com/group/repo.git` → Tailscale → ALB | PAT |
| Admin shell | SSM Session Manager → GitLab EC2 | AWS IAM |

### Tailscale ACL Policy

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
  }
}
```

### DNS & TLS

- Route 53 Private Hosted Zone in GitLab AWS account
- `gitlab.yourcompany.com` → ALB alias record
- ACM certificate with DNS validation (cross-account: Terraform assumes role in DNS account)
- TLS terminated at ALB; GitLab runs HTTP on port 80

### PATs

- Developers create PATs in GitLab profile for HTTPS Git + API access
- Scopes: `read_repository`, `write_repository`, `api` as needed
- Team policy: rotate every 90 days (enforced by runbook, not software)

## Security Hardening

### AWS-Level Controls

| Control | Implementation | NIST 800-53 |
|---------|---------------|-------------|
| Encryption at rest | EBS gp3 encrypted (KMS), S3 SSE | SC-28 |
| Encryption in transit | TLS 1.2+ on ALB, Tailscale WireGuard | SC-8 |
| Audit logging | CloudTrail, VPC Flow Logs, ALB access logs | AU-2, AU-3 |
| Access control | IAM least-privilege, SSM, Tailscale ACLs | AC-2, AC-3, AC-6 |
| Network segmentation | Private subnet, no public IPs, SG allowlisting | SC-7 |
| Backup & recovery | Daily S3 backups, cross-region replication | CP-9, CP-10 |
| Secrets management | Secrets Manager, no secrets in state/git | SC-12 |
| FIPS crypto | Amazon Linux 2023 FIPS mode | SC-13 |

### Security Groups

```
ALB SG:
  Inbound:  443 from VPC CIDR (10.0.0.0/16)
  Outbound: 80 to GitLab SG

GitLab SG:
  Inbound:  80 from ALB SG
            22 from VPC CIDR (Git SSH via Tailscale)
  Outbound: 443 to 0.0.0.0/0 (via NAT — updates, Tailscale)
            443 to VPC endpoint prefix lists
```

### Emergency Access

1. Admin connects via SSM Session Manager (AWS IAM + MFA)
2. Root password from Secrets Manager for GitLab web UI
3. Root account retains password auth as override
4. Test quarterly

### Future Compliance Work (Not In Scope Now)

- AWS WAF on ALB
- Centralized SIEM/log aggregation
- AWS Inspector vulnerability scanning
- SSM Patch Manager baselines
- Formal incident response plan
- MFA enforcement (currently via Google Workspace policy)

## Terraform Module Structure

```
terraform/
├── backend.tf
├── variables.tf
├── outputs.tf
├── main.tf
├── terraform.tfvars          # git-ignored
│
├── modules/
│   ├── networking/
│   │   ├── vpc.tf
│   │   ├── flow_logs.tf
│   │   ├── endpoints.tf
│   │   └── security_groups.tf
│   ├── alb/
│   │   ├── alb.tf
│   │   ├── acm.tf
│   │   └── logging.tf
│   ├── gitlab/
│   │   ├── ec2.tf
│   │   ├── iam.tf
│   │   ├── user_data.sh
│   │   └── backup.tf
│   ├── dns/
│   │   ├── route53.tf
│   │   └── providers.tf     # Cross-account role assumption
│   ├── monitoring/
│   │   ├── cloudtrail.tf
│   │   └── cloudwatch.tf
│   └── tailscale/
│       └── auth_key.tf
│
└── bootstrap/
    ├── state_backend.tf
    └── README.md
```

### Cross-Account DNS

- DNS hosted zone lives in a separate AWS account
- Terraform `dns` module uses an aliased provider with `sts:AssumeRole`
- Role in DNS account permits creating ACM validation CNAME records
- Private hosted zone lives in the GitLab account VPC (no cross-account needed)

### Secrets Management

Secrets stored in AWS Secrets Manager (values populated manually after `terraform apply`):

- `gitlab/root-password`
- `gitlab/oauth/client-id`
- `gitlab/oauth/client-secret`
- `gitlab/tailscale/auth-key`
- `gitlab/secrets-json` (backup of gitlab-secrets.json)

### State Management

- S3 bucket with versioning + KMS encryption
- DynamoDB table for state locking
- `bootstrap/` directory run once manually to create these
- 90-day version retention

## Deployment Phases

### Phase 1: AWS Foundation
- Bootstrap Terraform state backend
- VPC, subnets, NAT Gateway, route tables
- VPC endpoints
- VPC Flow Logs, CloudTrail
- Security groups

### Phase 2: GitLab Infrastructure
- Secrets Manager entries (created empty)
- IAM role + instance profile
- EC2 instance with user_data
- EBS data volume
- S3 backup bucket with lifecycle + cross-region replication

### Phase 3: Load Balancer & DNS
- ACM certificate (cross-account DNS validation)
- Internal ALB, listener, target group
- Route 53 private hosted zone + ALB alias record

### Phase 4: Access Layer
- Tailscale on GitLab EC2 via user_data
- Tailscale ACL policy documented
- SSM Session Manager verified

### Phase 5: GitLab Configuration & Auth
- Populate Secrets Manager values
- First boot / reconfigure
- Verify Google OAuth login
- Harden settings, set defaults to private
- Create initial groups/projects

### Phase 6: Operational Readiness
- Verify backup + restore procedure
- Set up cron for daily backups
- CloudWatch alarms (disk >80%, CPU >90%, StatusCheckFailed)

### Phase 7: Documentation
- `docs/quick-start.html` — developer onboarding: install Tailscale, authenticate, clone first repo, create PAT, SSH key setup
- `docs/cmmc-l2-gap-analysis.md` — map all 110 CMMC Level 2 practices (NIST 800-171) against current implementation, classify as Implemented / Partially Implemented / Gap, identify remediation steps
- `docs/fedramp-moderate-gap-analysis.md` — map NIST 800-53 moderate baseline controls, same classification, distinguish infrastructure vs. policy vs. procedural gaps
