# DoD IL2 Compliance Mapping -- Self-Hosted GitLab CE on AWS

**System**: GitLab CE (self-hosted) on AWS EC2
**Region**: Selectable via `aws_region` variable (default: us-east-1, N. Virginia, commercial)
**Date**: 2026-03-03 (updated)
**Classification**: Impact Level 2 (IL2) -- Non-CUI Public and Some CUI

---

## 1. Overview

### What Is DoD IL2?

DoD Impact Level 2 (IL2) covers non-Controlled Unclassified Information (non-CUI) that is publicly releasable, as well as some low-sensitivity CUI. IL2 is defined in the DoD Cloud Computing Security Requirements Guide (CC SRG) and maps directly to:

- **FedRAMP Moderate** baseline (minimum requirement)
- **NIST SP 800-53 Rev 5** Moderate controls

IL2 workloads do **not** require GovCloud or dedicated infrastructure. Any commercial AWS region with FedRAMP authorization satisfies IL2 hosting requirements.

### Why Commercial AWS (us-east-1) Qualifies

AWS commercial regions, including us-east-1, hold **FedRAMP High** Provisional Authorization to Operate (P-ATO), which exceeds the IL2 requirement of FedRAMP Moderate. The DoD CC SRG explicitly permits IL2 workloads in FedRAMP-authorized commercial cloud offerings. GovCloud is required only for IL4+ workloads.

### This Deployment

This GitLab instance runs on a single EC2 instance in a private subnet with no public IP. User access is through a public-facing Application Load Balancer protected by AWS WAF, with TLS 1.3 termination at the ALB. AWS WAF enforces OWASP common rules, known bad input filtering, and rate limiting. Authentication uses GitLab native authentication with mandatory two-factor authentication (TOTP) for all users, 15-character minimum passwords, and 60-minute session timeouts. Git operations use HTTPS only with Personal Access Tokens (PATs); SSH access is not enabled. Admin access is via SSM Session Manager only. All encryption uses Customer Managed KMS Keys (CMKs). Continuous monitoring is provided by GuardDuty, Security Hub (NIST 800-53 v5), and AWS Config. Infrastructure is fully defined in Terraform with Checkov policy scanning (265 passed, 0 failed).

---

## 2. Control Mapping by NIST 800-53 Family

### AC -- Access Control

| Control Area | Status | Implementation |
|---|---|---|
| AC-2 Account Management | Implemented | GitLab native authentication with admin-only account creation (`gitlab_signup_enabled = false`). GitLab RBAC manages project/group access. Root password stored in Secrets Manager with CMK encryption (`modules/gitlab/secrets.tf`). |
| AC-2(3) Inactive Accounts | Implemented | Lambda function (`modules/lambda-user-deactivation/`) runs weekly via EventBridge to deactivate GitLab users inactive for >90 days. Uses GitLab Admin API with PAT stored in Secrets Manager. Skips admin and bot accounts. SNS notifications on deactivations. Supports `DRY_RUN` mode for safe rollout. |
| AC-3 Access Enforcement | Implemented | Security groups restrict ALB ingress to port 443 only, with AWS WAF filtering all requests (`modules/networking/security_groups.tf`). EC2 instance accepts HTTP only from ALB SG. No SSH (port 22) ingress on EC2. IAM policies scoped to least privilege (`modules/gitlab/iam.tf`). |
| AC-4 Information Flow | Implemented | Public ALB with AWS WAF and TLS 1.3 termination (`modules/alb/alb.tf`). WAF applies OWASP common rules, known bad input filtering, and rate limiting (`modules/waf/waf.tf`). EC2 in private subnet routed through NAT Gateway (`modules/networking/vpc.tf`). VPC endpoints keep AWS API traffic off the internet (`modules/networking/endpoints.tf`). |
| AC-7 Unsuccessful Logon | Implemented | GitLab CE enforces account lockout after failed attempts. AWS WAF rate limiting (2000 requests per 5 minutes per IP) mitigates brute-force attacks at the network edge (`modules/waf/waf.tf`). |
| AC-8 Login Banner | Implemented | Standard DoD consent banner configured via `gitlab_rails['extra_sign_in_text']` in `user_data.sh` gitlab.rb. Banner displays the USG-authorized use notice and monitoring consent text on the GitLab sign-in page. |
| AC-17 Remote Access | Implemented | All access via public HTTPS with GitLab native authentication + mandatory 2FA. TLS 1.3 enforced at the ALB (`ELBSecurityPolicy-TLS13-1-2-2021-06`). AWS WAF protects against common web exploits. Admin access via SSM Session Manager only -- no SSH keys (`modules/gitlab/iam.tf`). Git operations use HTTPS with PATs; no SSH access is exposed. |

### AU -- Audit and Accountability

| Control Area | Status | Implementation |
|---|---|---|
| AU-2 Event Logging | Implemented | Multi-region CloudTrail captures all AWS API calls with CloudWatch Logs integration (`modules/monitoring/cloudtrail.tf`). VPC Flow Logs capture all network traffic at 60-second intervals (`modules/networking/flow_logs.tf`). ALB access logs capture all HTTP requests (`modules/alb/logging.tf`). WAF logs capture all evaluated requests to CloudWatch Logs (`modules/waf/waf.tf`). S3 access logging enabled on all buckets via dedicated log target bucket (`modules/networking/s3_access_logs.tf`). GitLab application audit events enabled. |
| AU-3 Content of Audit Records | Implemented | CloudTrail records include who, what, when, where, and outcome for every API call. Log file validation enabled (`enable_log_file_validation = true`). |
| AU-6 Audit Review/Analysis | Partially Implemented | Logs collected and stored. CloudWatch alarms alert on instance health and unauthorized API calls (`modules/monitoring/cloudwatch.tf`). SNS topic delivers alarm notifications (`aws_sns_topic.alerts`). Security Hub provides aggregated security findings. **Gap**: No centralized SIEM for automated log correlation. |
| AU-9 Protection of Audit Info | Implemented | All log buckets have public access blocked, S3 versioning enabled, and CMK encryption (`modules/monitoring/cloudtrail.tf`, `modules/networking/flow_logs.tf`). CloudTrail encrypted with dedicated CMK (`modules/kms/main.tf`, `cloudtrail` key). CloudTrail log file validation prevents tampering. |
| AU-12 Audit Record Generation | Implemented | CloudTrail multi-region trail, VPC flow logs (60s aggregation), ALB access logs, WAF logs, and S3 access logs all generate automatically. AWS Config records all resource configuration changes (`modules/security/config.tf`). |
| AU-11 Audit Record Retention | Implemented | All log buckets transition to Glacier at 30-90 days and expire at 365 days. CloudWatch log groups retain for 365 days. CloudTrail: 90d to Glacier, 365d expiry. Flow Logs and ALB Logs: 30d to Glacier, 365d expiry. |

### CA -- Security Assessment and Authorization

| Control Area | Status | Implementation |
|---|---|---|
| CA-7 Continuous Monitoring | Implemented | GuardDuty threat detection with S3 log monitoring (`modules/security/guardduty.tf`). Security Hub with NIST 800-53 v5 and AWS Foundational Security Best Practices standards (`modules/security/securityhub.tf`). AWS Config records all resource configurations (`modules/security/config.tf`). Checkov IaC scanning enforces security policies pre-deploy (265 passed, 0 failed, 30 skipped with justification). |

### CM -- Configuration Management

| Control Area | Status | Implementation |
|---|---|---|
| CM-2 Baseline Configuration | Implemented | Entire infrastructure defined as Terraform IaC (`main.tf` and `modules/`). EC2 instance built from Amazon Linux 2023 AMI with templated `user_data.sh`. GitLab configured via `gitlab.rb` template. AWS Config continuously records baseline configuration state. |
| CM-3 Configuration Change Control | Implemented | All changes go through Terraform plan/apply workflow. Checkov scans enforce security policies pre-deploy. Git history provides full change audit trail. AWS Config detects configuration drift. |
| CM-6 Configuration Settings | Implemented | ALB enforces TLS 1.3 minimum (`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`). IMDSv2 required on EC2 (`http_tokens = "required"`). Invalid header fields dropped on ALB (`drop_invalid_header_fields = true`). KMS key rotation enabled on all CMKs. |
| CM-7 Least Functionality | Implemented | Security groups allow only required ports: 443 inbound on ALB, 80 from ALB to EC2. No SSH access permitted. SSH daemon removed from EC2 bootstrap. Git operations are HTTPS-only with PATs (`modules/networking/security_groups.tf`). |

### CP -- Contingency Planning

| Control Area | Status | Implementation |
|---|---|---|
| CP-9 System Backup | Implemented | Daily GitLab data backups to S3 with versioning enabled (`modules/gitlab/backup.tf`). Daily config backups (`/etc/gitlab/`) uploaded to S3 (`user_data.sh` cron). Backups transition to Glacier at 30 days, expire at 365 days. `gitlab-secrets.json` backed up to Secrets Manager (`modules/gitlab/secrets.tf`). All backup data encrypted with CMK. |
| CP-10 System Recovery | Implemented | Recovery procedure: launch new EC2 from Terraform, restore from S3 backup, restore secrets from Secrets Manager. Separate data volume (`modules/gitlab/ec2.tf`) allows independent recovery. |
| CP-6 Alternate Storage | Partially Implemented | Backup replication region configured via `backup_replication_region` variable. **Note**: Cross-region replication resources should be verified as deployed. |

### IA -- Identification and Authentication

| Control Area | Status | Implementation |
|---|---|---|
| IA-2 User Identification | Implemented | GitLab native authentication with admin-managed accounts. Signup disabled (`gitlab_signup_enabled = false`). All user accounts created by GitLab administrators only. |
| IA-2(1) MFA | Implemented | Two-factor authentication required for all users (`require_two_factor_authentication = true`). Zero grace period -- users must configure TOTP immediately on next login (`two_factor_authentication_grace_period = 0`). Configured in `user_data.sh` gitlab.rb. |
| IA-5 Authenticator Management | Implemented | 15-character minimum password length (`password_minimum_length = 15`). Root password managed in Secrets Manager with CMK encryption (`modules/gitlab/secrets.tf`). Git operations authenticated via HTTPS Personal Access Tokens (PATs). No static SSH keys for admin access (SSM used instead). |
| IA-5(1) Authenticator Rotation | Implemented | Secrets Manager root password secret rotated automatically every 90 days via Lambda (`modules/rotation/`). Rotation uses the standard 4-step Secrets Manager pattern (createSecret, setSecret, testSecret, finishSecret). Password applied to GitLab via SSM Run Command with `gitlab-rails runner`. Password handoff uses temporary SSM SecureString parameters (never in shell args). AWSPREVIOUS label preserves rollback capability. |
| IA-8 Non-Org User ID | Implemented | Signup disabled. Only administrators can create accounts. Default visibility set to private for all projects, groups, and snippets. |

### IR -- Incident Response

| Control Area | Status | Implementation |
|---|---|---|
| IR-4 Incident Handling | Implemented | CloudWatch alarms on CPU (>90%), status check failures, and unauthorized API calls with SNS notification (`modules/monitoring/cloudwatch.tf`). CloudTrail provides forensic investigation capability. GuardDuty provides automated threat detection. Security Hub aggregates findings. WAF metrics and logs provide visibility into blocked threats. Formal Incident Response Plan documented (`docs/incident-response-plan.md`) per NIST 800-61r2 with roles, severity classification, containment strategies, and response runbooks. |
| IR-5 Incident Monitoring | Implemented | GuardDuty threat detection (`modules/security/guardduty.tf`). Security Hub finding aggregation (`modules/security/securityhub.tf`). CloudWatch alarms with SNS alerting. WAF logging to CloudWatch. CloudTrail integrated with CloudWatch Logs for real-time analysis. |
| IR-6 Incident Reporting | Implemented | Incident reporting procedures documented in the Incident Response Plan (`docs/incident-response-plan.md`), including contact list, notification timelines, DoD reporting requirements, and report formats. |

### MP -- Media Protection

| Control Area | Status | Implementation |
|---|---|---|
| MP-3 Media Marking | Partially Implemented | `DataClassification = "IL2"` tag applied to all resources via provider `default_tags` (`main.tf`). **Gap**: No FISMA System ID or System Owner tags. |

### RA -- Risk Assessment

| Control Area | Status | Implementation |
|---|---|---|
| RA-5 Vulnerability Scanning | Implemented | Amazon Inspector v2 enabled for continuous EC2 CVE scanning (`modules/security/inspector.tf`). Findings automatically flow to Security Hub. Security Hub checks against NIST 800-53 and AWS best practices. GuardDuty monitors for known threats. Checkov scans IaC for misconfigurations. |

### SC -- System and Communications Protection

| Control Area | Status | Implementation |
|---|---|---|
| SC-5 Denial of Service | Implemented | AWS WAF rate limiting at 2000 requests per 5 minutes per IP (`modules/waf/waf.tf`). ALB inherently distributes load. GitLab application-level rate limiting configured in `gitlab.rb`. |
| SC-7 Boundary Protection | Implemented | EC2 in private subnets with no public IP (`modules/networking/vpc.tf`). Public ALB with AWS WAF. WAF enforces AWSManagedRulesCommonRuleSet (OWASP Top 10), AWSManagedRulesKnownBadInputsRuleSet, and rate limiting. VPC endpoints eliminate internet traversal for AWS API calls (`modules/networking/endpoints.tf`). |
| SC-8 Transmission Confidentiality | Implemented | ALB terminates TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`). All user and Git traffic encrypted via HTTPS. VPC endpoint traffic stays on AWS private network. **Note**: ALB-to-EC2 traffic is HTTP within the private subnet; end-to-end TLS is a future enhancement. |
| SC-12 Cryptographic Key Management | Implemented | Customer Managed KMS Keys (CMKs) with automatic annual rotation for all encryption (`modules/kms/main.tf`): general-purpose key (S3, Secrets Manager), dedicated CloudTrail key with service-scoped policy, and EBS encryption key. ACM manages TLS certificates (`modules/alb/acm.tf`). |
| SC-13 Cryptographic Protection | Implemented | FIPS-validated AMI recommended in `user_data.sh`. TLS 1.3 enforced on ALB. CMK encryption at rest for all data stores. KMS key policies restrict usage to account root and authorized services. |
| SC-28 Protection of Information at Rest | Implemented | EBS root and data volumes encrypted with EBS CMK (`modules/gitlab/ec2.tf`). All S3 buckets encrypted with general CMK (backups, CloudTrail, flow logs, Config) or AES-256 (ALB logs, which do not support KMS). Secrets Manager secrets encrypted with general CMK. Public access blocked on every bucket. |

### SI -- System and Information Integrity

| Control Area | Status | Implementation |
|---|---|---|
| SI-2 Flaw Remediation | Implemented | Amazon Linux 2023 provides security updates via `dnf`. Amazon Inspector v2 provides continuous automated CVE scanning on the EC2 instance (`modules/security/inspector.tf`). Inspector findings integrate with Security Hub for centralized vulnerability tracking. |
| SI-3 Malicious Code Protection | Implemented | ClamAV antimalware installed on EC2 via `user_data.sh` with daily signature updates (`freshclam`) and daily scans of GitLab data directories (`/var/opt/gitlab/git-data/`, `/var/opt/gitlab/uploads/`). Scan logs shipped to CloudWatch Logs for alerting. GuardDuty Malware Protection enabled for automated EBS malware scanning on threat detection (`modules/security/guardduty.tf`). |
| SI-4 System Monitoring | Implemented | CloudWatch detailed monitoring enabled on EC2. CPU, status check, and unauthorized API call alarms with SNS notification (`modules/monitoring/cloudwatch.tf`). CloudTrail monitors API activity with CloudWatch Logs integration. VPC Flow Logs monitor network traffic at 60-second intervals. WAF logs capture all evaluated requests. GuardDuty provides automated threat detection. Security Hub provides centralized findings dashboard. AWS Config monitors configuration compliance. |
| SI-5 Security Alerts | Implemented | CloudWatch alarms deliver via SNS topic. Security Hub aggregates findings. Daily Lambda (`modules/lambda-cisa-alerts/`) polls the CISA Known Exploited Vulnerabilities (KEV) catalog and sends SNS notifications for new entries. Amazon Inspector also integrates CISA KEV data into its vulnerability findings. |

---

## 3. IL2 Hosting Requirement Confirmation

| Requirement | Status | Evidence |
|---|---|---|
| Cloud provider must hold FedRAMP authorization at Moderate or higher | Satisfied | AWS holds FedRAMP **High** P-ATO, exceeding the Moderate minimum for IL2. |
| GovCloud required? | **No** | The DoD CC SRG permits IL2 workloads on any FedRAMP-authorized commercial cloud. GovCloud (IL4/IL5) is not required. |
| Region used | Selectable | Default us-east-1 (N. Virginia), configurable via `aws_region` variable in `terraform.tfvars`. All US commercial regions are within the FedRAMP High authorization boundary. |
| Data classification supported | IL2 | Non-CUI public data and low-sensitivity CUI. This deployment does not process CUI requiring IL4+ protections. |
| Data residency | US-only | All resources remain within the selected US region. S3 buckets and EBS volumes are region-bound. Backup replication targets a second US region. |
| Encryption key management | CMK | All encryption uses Customer Managed KMS Keys with automatic rotation (`modules/kms/main.tf`). |

---

## 4. Residual Gaps and Remediation Plan

### Resolved Gaps

The following gaps have been remediated:

| Gap | NIST Control | Resolution |
|---|---|---|
| No formal Incident Response Plan | IR-1, IR-6, IR-8 | IRP documented per NIST 800-61r2 (`docs/incident-response-plan.md`). |
| No vulnerability scanning | SI-2, RA-5 | Amazon Inspector v2 enabled (`modules/security/inspector.tf`). |
| No formal System Security Plan (SSP) | PL-2 | SSP documented per NIST 800-18 (`docs/system-security-plan.md`). |
| No login banner | AC-8 | DoD consent banner configured in `user_data.sh` gitlab.rb. |
| No inactive account deprovisioning | AC-2(3) | Weekly Lambda deactivates users inactive >90 days (`modules/lambda-user-deactivation/`). |
| Secrets rotation not automated | IA-5(1) | Lambda-based 90-day rotation for root password (`modules/rotation/`). |
| No dedicated antimalware | SI-3 | ClamAV on EC2 + GuardDuty Malware Protection enabled. |
| No automated advisory ingestion | SI-5 | Daily CISA KEV monitoring Lambda (`modules/lambda-cisa-alerts/`). |

### Remaining Gaps

| # | Gap | NIST Control | Priority | Remediation |
|---|---|---|---|---|
| 1 | No centralized log analysis / SIEM | AU-6, SI-4 | High | Deploy Amazon OpenSearch or integrate with a SIEM (e.g., Splunk, Elastic). Create CloudWatch Logs Insights queries for security events. |
| 2 | No security awareness training program | AT-2 | Medium | Establish annual security awareness training for all users. Document completion records. |
| 3 | ALB-to-EC2 traffic unencrypted | SC-8 | Medium | Configure GitLab nginx for HTTPS internally; update ALB target group to HTTPS. Traffic is within a private subnet but end-to-end TLS is preferred. |
| 4 | Backup bucket access logging | AU-2 | Low | Pass S3 access-logs bucket ID through to the GitLab module. Tracked as TODO in `modules/gitlab/backup.tf`. |

### Prioritized Next Steps

1. **30 days** -- Deploy centralized log analysis (OpenSearch or SIEM integration); enable end-to-end TLS (ALB-to-EC2 HTTPS).
2. **60 days** -- Establish security awareness training program; configure backup bucket access logging.
3. **Ongoing** -- Conduct IRP tabletop exercises; review and update SSP quarterly; rotate GitLab admin PAT.

---

## 5. Terraform Module Reference

| Module | Path | Relevant Controls |
|---|---|---|
| KMS | `modules/kms/main.tf` | SC-12, SC-13, SC-28 (CMKs for general, CloudTrail, EBS encryption) |
| Networking | `modules/networking/vpc.tf` | SC-7 (private subnets, NAT Gateway) |
| Security Groups | `modules/networking/security_groups.tf` | AC-3, AC-4, SC-7 (least-privilege network rules) |
| VPC Endpoints | `modules/networking/endpoints.tf` | SC-7, SC-8 (private AWS API access) |
| VPC Flow Logs | `modules/networking/flow_logs.tf` | AU-2, AU-9, AU-12 (network traffic logging, 60s interval) |
| S3 Access Logs | `modules/networking/s3_access_logs.tf` | AU-2, AU-12 (S3 access audit trail) |
| ALB | `modules/alb/alb.tf` | SC-7, SC-8 (public ALB, TLS 1.3) |
| ALB Logging | `modules/alb/logging.tf` | AU-2 (HTTP access logs with S3 access logging) |
| ACM Certificate | `modules/alb/acm.tf` | SC-12 (TLS certificate management) |
| WAF | `modules/waf/waf.tf` | AC-4, AC-7, SC-5, SC-7 (OWASP rules, rate limiting, WAF logging) |
| EC2 Instance | `modules/gitlab/ec2.tf` | CM-6 (IMDSv2, CMK-encrypted volumes) |
| IAM | `modules/gitlab/iam.tf` | AC-3, AC-6 (least-privilege IAM policies) |
| Secrets | `modules/gitlab/secrets.tf` | IA-5, SC-28 (CMK-encrypted credential management) |
| Backups | `modules/gitlab/backup.tf` | CP-9 (CMK-encrypted backups, config backups to S3, Glacier lifecycle) |
| CloudTrail | `modules/monitoring/cloudtrail.tf` | AU-2, AU-3, AU-9 (multi-region, CMK-encrypted, CloudWatch Logs integration) |
| CloudWatch | `modules/monitoring/cloudwatch.tf` | SI-4, IR-4 (health + security alarms, SNS alerting) |
| GuardDuty | `modules/security/guardduty.tf` | CA-7, IR-5, SI-3, SI-4 (threat detection, malware protection) |
| Security Hub | `modules/security/securityhub.tf` | CA-7, RA-5 (NIST 800-53 v5 + AWS best practices standards) |
| AWS Config | `modules/security/config.tf` | CA-7, CM-2, CM-3 (configuration compliance recording) |
| Inspector | `modules/security/inspector.tf` | RA-5, SI-2 (EC2 CVE scanning, CISA KEV integration) |
| User Deactivation | `modules/lambda-user-deactivation/` | AC-2(3) (automated inactive account deactivation) |
| Secrets Rotation | `modules/rotation/` | IA-5(1) (automated root password rotation via Secrets Manager) |
| CISA Alerts | `modules/lambda-cisa-alerts/` | SI-5 (CISA KEV advisory monitoring and SNS notification) |
| Bootstrap | `bootstrap/state_backend.tf` | CM-3 (versioned, encrypted Terraform state with lifecycle) |
