# DoD IL2 Compliance Mapping -- Self-Hosted GitLab CE on AWS

**System**: GitLab CE (self-hosted) on AWS EC2
**Region**: us-east-1 (N. Virginia, commercial)
**Date**: 2026-03-03
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

This GitLab instance runs on a single EC2 instance in a private subnet with no public internet ingress. All user access is through a Tailscale VPN mesh, with an internal ALB handling TLS termination. Authentication is via Google OAuth with organization-restricted accounts. Infrastructure is fully defined in Terraform with Checkov policy scanning.

---

## 2. Control Mapping by NIST 800-53 Family

### AC -- Access Control

| Control Area | Status | Implementation |
|---|---|---|
| AC-2 Account Management | Implemented | Google OAuth restricts login to organization domain (`google_oauth_hd` variable). GitLab RBAC manages project/group access. OAuth credentials stored in Secrets Manager (`modules/gitlab/secrets.tf`). |
| AC-3 Access Enforcement | Implemented | Security groups restrict ALB ingress to VPC CIDR only (`modules/networking/security_groups.tf`, lines 6-12). EC2 instance accepts HTTP only from ALB SG (lines 72-80). IAM policies scoped to least privilege (`modules/gitlab/iam.tf`). |
| AC-4 Information Flow | Implemented | Internal ALB with no public listener (`modules/alb/alb.tf`, `internal = true`). EC2 in private subnet routed through NAT Gateway (`modules/networking/vpc.tf`). VPC endpoints keep AWS API traffic off the internet (`modules/networking/endpoints.tf`). |
| AC-7 Unsuccessful Logon | Partially Implemented | GitLab CE enforces account lockout after failed attempts (configurable in `gitlab.rb`). Tailscale requires device authorization before network access. |
| AC-17 Remote Access | Implemented | All access requires Tailscale VPN (WireGuard). No public endpoints exist. Admin access via SSM Session Manager only -- no SSH keys (`modules/gitlab/iam.tf`, SSM policy attachment line 31). |

### AU -- Audit and Accountability

| Control Area | Status | Implementation |
|---|---|---|
| AU-2 Event Logging | Implemented | CloudTrail captures all AWS API calls (`modules/monitoring/cloudtrail.tf`). VPC Flow Logs capture all network traffic (`modules/networking/flow_logs.tf`). ALB access logs capture all HTTP requests (`modules/alb/logging.tf`). GitLab application audit events enabled in `gitlab.rb`. |
| AU-3 Content of Audit Records | Implemented | CloudTrail records include who, what, when, where, and outcome for every API call. Log file validation enabled (`enable_log_file_validation = true`). |
| AU-6 Audit Review/Analysis | Partially Implemented | Logs are collected and stored. CloudWatch alarms alert on instance health (`modules/monitoring/cloudwatch.tf`). **Gap**: No centralized SIEM for automated log correlation. |
| AU-9 Protection of Audit Info | Implemented | All log buckets have public access blocked and KMS encryption (`modules/monitoring/cloudtrail.tf`, lines 38-44; `modules/networking/flow_logs.tf`, lines 35-41). CloudTrail bucket uses `aws:kms` SSE. |
| AU-11 Audit Record Retention | Implemented | All log buckets transition to Glacier at 30-90 days and expire at 365 days. CloudTrail: 90d to Glacier, 365d expiry. Flow Logs and ALB Logs: 30d to Glacier, 365d expiry. |

### CM -- Configuration Management

| Control Area | Status | Implementation |
|---|---|---|
| CM-2 Baseline Configuration | Implemented | Entire infrastructure defined as Terraform IaC (`main.tf` and `modules/`). EC2 instance built from Amazon Linux 2023 AMI with templated `user_data.sh`. GitLab configured via `gitlab.rb` template. |
| CM-3 Configuration Change Control | Implemented | All changes go through Terraform plan/apply workflow. Checkov scans enforce security policies pre-deploy. Git history provides full change audit trail. |
| CM-6 Configuration Settings | Implemented | ALB enforces TLS 1.3 minimum (`ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` in `modules/alb/alb.tf`, line 53). IMDSv2 required on EC2 (`http_tokens = "required"` in `modules/gitlab/ec2.tf`, line 40). Invalid header fields dropped on ALB (`drop_invalid_header_fields = true`). |
| CM-7 Least Functionality | Implemented | Security groups allow only required ports: 443 inbound on ALB, 80 from ALB to EC2, 22 from VPC for Git SSH (`modules/networking/security_groups.tf`). No unnecessary services exposed. |

### CP -- Contingency Planning

| Control Area | Status | Implementation |
|---|---|---|
| CP-9 System Backup | Implemented | Daily GitLab backups to S3 with versioning enabled (`modules/gitlab/backup.tf`). Backups transition to Glacier at 30 days, expire at 365 days. `gitlab-secrets.json` backed up to Secrets Manager (`modules/gitlab/secrets.tf`, line 29). |
| CP-10 System Recovery | Implemented | Recovery procedure: launch new EC2 from Terraform, restore from S3 backup, restore secrets from Secrets Manager. Separate data volume (`modules/gitlab/ec2.tf`, lines 54-70) allows independent recovery. |
| CP-6 Alternate Storage | Partially Implemented | Backup replication region configured via `backup_replication_region` variable (`main.tf`, line 14). **Note**: Cross-region replication resources should be verified as deployed. |

### IA -- Identification and Authentication

| Control Area | Status | Implementation |
|---|---|---|
| IA-2 User Identification | Implemented | Google OAuth enforces organization-specific accounts via `google_oauth_hd` domain restriction. OAuth credentials stored in Secrets Manager (`modules/gitlab/secrets.tf`, lines 8-20). |
| IA-2(1) MFA | Implemented | Google Workspace enforces MFA at the IdP level. All GitLab logins go through Google OAuth, inheriting MFA enforcement. |
| IA-5 Authenticator Management | Implemented | OAuth client secrets managed in AWS Secrets Manager. Tailscale auth keys managed in Secrets Manager (`modules/gitlab/secrets.tf`, lines 22-27). No static SSH keys for admin access (SSM used instead). |
| IA-8 Non-Org User ID | Implemented | Google OAuth `hd` parameter restricts login to organization domain only. No local GitLab account registration permitted. |

### IR -- Incident Response

| Control Area | Status | Implementation |
|---|---|---|
| IR-4 Incident Handling | Partially Implemented | CloudWatch alarms on CPU (>90%) and status check failures (`modules/monitoring/cloudwatch.tf`). CloudTrail provides forensic investigation capability. **Gap**: No formal incident response plan documented. |
| IR-5 Incident Monitoring | Partially Implemented | Logging infrastructure is in place (CloudTrail, Flow Logs, ALB logs). **Gap**: No automated alerting on security events or SIEM integration. |
| IR-6 Incident Reporting | Gap | No formal incident reporting procedures or contact lists documented. |

### SC -- System and Communications Protection

| Control Area | Status | Implementation |
|---|---|---|
| SC-7 Boundary Protection | Implemented | EC2 in private subnets with no public IP (`modules/networking/vpc.tf`, lines 36-45). Internal ALB only (`modules/alb/alb.tf`, `internal = true`). ALB SG restricts ingress to VPC CIDR (`modules/networking/security_groups.tf`, lines 6-12). VPC endpoints eliminate internet traversal for AWS API calls (`modules/networking/endpoints.tf`). |
| SC-8 Transmission Confidentiality | Implemented | ALB terminates TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`). Tailscale uses WireGuard encryption for all VPN traffic. VPC endpoint traffic stays on AWS private network. |
| SC-12 Cryptographic Key Management | Implemented | AWS KMS manages encryption keys for EBS (`modules/gitlab/ec2.tf`, `encrypted = true`), S3 buckets (`aws:kms` SSE), and Secrets Manager. ACM manages TLS certificates (`modules/alb/acm.tf`). |
| SC-13 Cryptographic Protection | Implemented | FIPS mode enabled on Amazon Linux 2023. TLS 1.3 enforced on ALB. KMS encryption at rest for all data stores. WireGuard for data in transit over VPN. |
| SC-28 Protection of Information at Rest | Implemented | EBS root and data volumes encrypted (`modules/gitlab/ec2.tf`, lines 28, 59). All S3 buckets encrypted with KMS (backups, CloudTrail, flow logs) or AES-256 (ALB logs, which do not support KMS). Public access blocked on every bucket. |

### SI -- System and Information Integrity

| Control Area | Status | Implementation |
|---|---|---|
| SI-2 Flaw Remediation | Partially Implemented | Amazon Linux 2023 provides security updates via `dnf`. EC2 user data can run updates at launch. **Gap**: No Amazon Inspector for automated vulnerability scanning. |
| SI-3 Malicious Code Protection | Partially Implemented | Amazon Linux 2023 includes kernel-level protections. GitLab monitors uploaded content. **Gap**: No dedicated antimalware scanning. |
| SI-4 System Monitoring | Implemented | CloudWatch detailed monitoring enabled (`monitoring = true` in `modules/gitlab/ec2.tf`, line 22). CPU and status check alarms configured (`modules/monitoring/cloudwatch.tf`). CloudTrail monitors API activity. VPC Flow Logs monitor network traffic. |
| SI-5 Security Alerts | Partially Implemented | CloudWatch alarms provide operational alerts. **Gap**: No subscription to US-CERT/CISA advisories or automated advisory ingestion. |

---

## 3. IL2 Hosting Requirement Confirmation

| Requirement | Status | Evidence |
|---|---|---|
| Cloud provider must hold FedRAMP authorization at Moderate or higher | Satisfied | AWS holds FedRAMP **High** P-ATO, exceeding the Moderate minimum for IL2. |
| GovCloud required? | **No** | The DoD CC SRG permits IL2 workloads on any FedRAMP-authorized commercial cloud. GovCloud (IL4/IL5) is not required. |
| Region used | us-east-1 | US East (N. Virginia) is within the FedRAMP High authorization boundary. |
| Data classification supported | IL2 | Non-CUI public data and low-sensitivity CUI. This deployment does not process CUI requiring IL4+ protections. |
| Data residency | US-only | us-east-1 is a CONUS region. S3 buckets and EBS volumes remain within the region. Backup replication targets a second US region. |

**Bottom line**: AWS commercial us-east-1 exceeds IL2 hosting requirements. No architecture changes are needed for IL2 eligibility. The focus is on implementing and documenting NIST 800-53 Moderate controls at the application and operating system layer.

---

## 4. Residual Gaps and Remediation Plan

| # | Gap | NIST Control | Priority | Remediation |
|---|---|---|---|---|
| 1 | No formal Incident Response Plan | IR-1, IR-6, IR-8 | High | Draft an IRP covering roles, escalation, communication, and forensic procedures. Conduct tabletop exercise. |
| 2 | No centralized log analysis / SIEM | AU-6, SI-4 | High | Deploy Amazon OpenSearch or integrate with a SIEM (e.g., Splunk, Elastic). Create CloudWatch Logs Insights queries for security events. |
| 3 | No vulnerability scanning | SI-2, RA-5 | High | Enable Amazon Inspector on the GitLab EC2 instance for continuous CVE scanning. Add Terraform resource for `aws_inspector2_enabler`. |
| 4 | No formal System Security Plan (SSP) | PL-2 | High | Document the SSP per NIST 800-18 format. This compliance mapping serves as a starting point but does not replace a formal SSP. |
| 5 | No login banner | AC-8 | Medium | Configure GitLab sign-in page banner and SSH pre-auth banner in `gitlab.rb` with DoD-required consent text. |
| 6 | No security awareness training program | AT-2 | Medium | Establish annual security awareness training for all users. Document completion records. |
| 7 | No inactive account deprovisioning | AC-2(3) | Medium | Configure GitLab to deactivate accounts after 90 days of inactivity. Automate with a scheduled rake task or API script. |
| 8 | No automated advisory ingestion | SI-5 | Low | Subscribe to CISA alerts and AWS Security Bulletins. Route to an ops channel. |

### Prioritized Next Steps

1. **Immediate** -- Enable Amazon Inspector; add login banner to `gitlab.rb`.
2. **30 days** -- Draft Incident Response Plan; configure inactive account deprovisioning.
3. **60 days** -- Deploy centralized log analysis; begin formal SSP documentation.
4. **90 days** -- Establish security awareness training program; complete SSP.

---

## Terraform Module Reference

| Module | Path | Relevant Controls |
|---|---|---|
| Networking | `modules/networking/vpc.tf` | SC-7 (private subnets, NAT Gateway) |
| Security Groups | `modules/networking/security_groups.tf` | AC-3, AC-4, SC-7 (least-privilege network rules) |
| VPC Endpoints | `modules/networking/endpoints.tf` | SC-7, SC-8 (private AWS API access) |
| VPC Flow Logs | `modules/networking/flow_logs.tf` | AU-2, AU-9 (network traffic logging) |
| ALB | `modules/alb/alb.tf` | SC-7, SC-8 (internal ALB, TLS 1.3) |
| ALB Logging | `modules/alb/logging.tf` | AU-2 (HTTP access logs) |
| ACM Certificate | `modules/alb/acm.tf` | SC-12 (TLS certificate management) |
| EC2 Instance | `modules/gitlab/ec2.tf` | CM-6 (IMDSv2, encrypted volumes, FIPS) |
| IAM | `modules/gitlab/iam.tf` | AC-3, AC-6 (least-privilege IAM policies) |
| Secrets | `modules/gitlab/secrets.tf` | IA-5, SC-28 (credential management) |
| Backups | `modules/gitlab/backup.tf` | CP-9 (encrypted backups, Glacier lifecycle) |
| CloudTrail | `modules/monitoring/cloudtrail.tf` | AU-2, AU-3, AU-9 (API audit logging) |
| CloudWatch | `modules/monitoring/cloudwatch.tf` | SI-4, IR-4 (health monitoring, alarms) |
