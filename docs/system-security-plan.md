# System Security Plan (SSP)

## GitLab CE on AWS (IL2)

| Field | Value |
|---|---|
| **Document Version** | 1.0 |
| **Date** | 2026-03-03 |
| **Classification** | DoD Impact Level 2 (IL2) |
| **Prepared By** | _[Name, Title]_ |
| **Reviewed By** | _[Name, Title]_ |
| **Approved By** | _[Authorizing Official Name, Title]_ |
| **Approval Date** | _[Pending]_ |

> This document follows the NIST SP 800-18 Rev 1 format: *Guide for Developing Security Plans for Federal Information Systems*.

---

## Table of Contents

1. [System Identification](#1-system-identification)
2. [System Description / Purpose](#2-system-description--purpose)
3. [System Environment](#3-system-environment)
4. [System Interconnections](#4-system-interconnections)
5. [Laws, Regulations, and Policies](#5-laws-regulations-and-policies)
6. [Security Control Summary](#6-security-control-summary)
7. [Minimum Security Controls](#7-minimum-security-controls)
8. [Personnel Security](#8-personnel-security)
9. [Physical and Environmental Security](#9-physical-and-environmental-security)
10. [Contingency Planning](#10-contingency-planning)
11. [Configuration Management](#11-configuration-management)
12. [Maintenance](#12-maintenance)
13. [System Integrity](#13-system-integrity)
14. [Plan Approval and Authorization](#14-plan-approval-and-authorization)

---

## 1. System Identification

| Field | Value |
|---|---|
| **System Name** | GitLab CE on AWS (IL2) |
| **System Abbreviation** | GITLAB-IL2 |
| **System Version** | 1.0 |
| **FISMA System ID** | _[To be assigned]_ |
| **Information System Category** | Moderate (FIPS 199) |
| **Data Classification** | DoD Impact Level 2 (IL2) -- Non-CUI public and low-sensitivity CUI |
| **Operational Status** | Operational |
| **System Type** | Major Application |

### System Owner and Key Roles

| Role | Name | Organization | Contact |
|---|---|---|---|
| System Owner | _[Name]_ | _[Organization]_ | _[Email / Phone]_ |
| Authorizing Official (AO) | _[Name]_ | _[Organization]_ | _[Email / Phone]_ |
| Information System Security Officer (ISSO) | _[Name]_ | _[Organization]_ | _[Email / Phone]_ |
| Information System Security Manager (ISSM) | _[Name]_ | _[Organization]_ | _[Email / Phone]_ |
| System Administrator | _[Name]_ | _[Organization]_ | _[Email / Phone]_ |

### Authorization Boundary

The authorization boundary encompasses all AWS resources provisioned by the Terraform infrastructure-as-code (IaC) within a single AWS account and region. This includes:

- **Compute**: Single EC2 instance (Amazon Linux 2023) running GitLab CE
- **Networking**: VPC with public and private subnets across 2 Availability Zones, NAT Gateway, VPC endpoints, security groups
- **Load Balancing and Edge Protection**: Application Load Balancer (ALB) with AWS WAF
- **Storage**: EBS volumes (root + data), S3 buckets (backups, logs, CloudTrail, Config)
- **Secrets Management**: AWS Secrets Manager secrets with CMK encryption
- **Encryption**: AWS KMS Customer Managed Keys (3 CMKs: general, CloudTrail, EBS)
- **Monitoring**: CloudTrail, CloudWatch, SNS
- **Security Services**: GuardDuty (with malware protection), Security Hub, AWS Config, Amazon Inspector
- **Automation**: Lambda functions (inactive user deactivation, secrets rotation, CISA KEV monitoring)
- **Identity**: IAM roles and policies, ACM certificates

**Excluded from boundary**: Parent DNS zone (agiledefense.xyz, separate AWS account), end-user workstations, AWS management plane (covered by AWS FedRAMP P-ATO).

---

## 2. System Description / Purpose

### Purpose

GitLab CE on AWS (IL2) provides a self-hosted source code management, CI/CD, and collaboration platform for Department of Defense personnel and contractors. The system hosts non-CUI public and low-sensitivity CUI source code repositories, issue trackers, and CI/CD pipelines on infrastructure aligned with DoD Impact Level 2 compliance requirements.

### Functional Description

The system provides the following capabilities:

- **Source Code Management**: Git-based version control with branch management, merge requests, and code review workflows
- **Issue Tracking**: Project management with issues, milestones, and boards
- **CI/CD Pipelines**: Automated build, test, and deployment pipelines
- **Container Registry**: Docker image storage and distribution (GitLab integrated registry)
- **Wiki and Documentation**: Project-level wikis and documentation hosting

### User Base

- **Total Users**: Admin-managed accounts only; self-registration is disabled
- **User Types**: Administrators, Developers, Maintainers, Guests
- **Authentication**: GitLab native authentication with mandatory TOTP-based two-factor authentication
- **Access Method**: HTTPS (web UI and Git over HTTPS with Personal Access Tokens); no SSH access

### Data Handled

| Data Type | Classification | Storage Location |
|---|---|---|
| Source code repositories | IL2 (Non-CUI / Low-sensitivity CUI) | EBS data volume (CMK-encrypted) |
| GitLab application database | IL2 | EBS data volume (CMK-encrypted) |
| User credentials (hashed) | IL2 | EBS data volume (CMK-encrypted) |
| GitLab root password | IL2 | AWS Secrets Manager (CMK-encrypted) |
| Backup archives | IL2 | S3 bucket (CMK-encrypted, versioned) |
| Audit logs | IL2 | S3 / CloudWatch Logs (CMK-encrypted) |
| CI/CD artifacts | IL2 | EBS data volume (CMK-encrypted) |

---

## 3. System Environment

### AWS Infrastructure

| Component | Detail |
|---|---|
| **Cloud Provider** | Amazon Web Services (AWS) |
| **AWS Authorization** | FedRAMP High Provisional ATO (P-ATO) |
| **Region** | Configurable via `aws_region` variable (default: `us-east-1`, N. Virginia, commercial) |
| **Account Type** | Commercial (non-GovCloud) |
| **Data Residency** | US-only; all resources region-bound |

### Network Architecture

The system deploys into a custom VPC spanning 2 Availability Zones:

```
Internet
   |
   v
[Route53 DNS (code.agiledefense.xyz)] --> [ALB + WAF (Public Subnets, 2 AZs)]
                          |
                     [TLS 1.3 termination]
                          |
                     [HTTPS/443 re-encryption]
                          |
                     [EC2 GitLab CE (Private Subnet)]
                          |
                     [NAT Gateway] --> Internet (outbound only)
                          |
                     [VPC Endpoints] --> AWS Services (private path)
```

**Public subnets** (2 AZs): Application Load Balancer, NAT Gateway

**Private subnets** (2 AZs): EC2 instance (GitLab CE), Lambda functions (ENIs)

**VPC Endpoints** (private connectivity to AWS services):

| Endpoint | Type | Purpose |
|---|---|---|
| S3 | Gateway | Backups, logs, state |
| SSM | Interface | Session Manager access |
| SSM Messages | Interface | Session Manager messaging |
| EC2 Messages | Interface | SSM agent communication |
| Secrets Manager | Interface | Secret retrieval |
| CloudWatch Logs | Interface | Log delivery |
| KMS | Interface | Encryption operations |

### Terraform Module Architecture

The infrastructure is defined entirely as Terraform IaC. The module dependency graph is:

```
kms --> networking --> gitlab
                  --> alb --> waf
        monitoring (depends on: gitlab.instance_id, kms)
        security (standalone, uses kms)
        user_deactivation (depends on: networking, kms, monitoring)
        rotation (depends on: networking, gitlab, kms)
        cisa_alerts (depends on: networking, kms, monitoring)
```

| Module | Path | Responsibility |
|---|---|---|
| **kms** | `modules/kms/` | 3 Customer Managed Keys: general (S3, Secrets Manager, CloudWatch, DynamoDB), CloudTrail-specific, EBS-specific. All keys have automatic annual rotation. |
| **networking** | `modules/networking/` | VPC, 2 public + 2 private subnets across 2 AZs, NAT Gateway, security groups, 7 VPC endpoints (S3 gateway + SSM, SSM Messages, EC2 Messages, Secrets Manager, CloudWatch Logs, KMS interfaces), VPC flow logs (60s aggregation), S3 access log bucket. |
| **gitlab** | `modules/gitlab/` | EC2 instance (Amazon Linux 2023), EBS root + data volumes (CMK-encrypted), IAM instance profile with least-privilege policies, S3 backup bucket (versioned, CMK-encrypted, lifecycle policies), Secrets Manager secrets, `user_data.sh` bootstrap script. |
| **alb** | `modules/alb/` | Internet-facing ALB, HTTPS listener with TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), ACM certificate (DNS validation via Route53), health checks on `/-/health`, access logging to S3. |
| **waf** | `modules/waf/` | WAFv2 WebACL with AWSManagedRulesCommonRuleSet (OWASP Top 10), AWSManagedRulesKnownBadInputsRuleSet, rate limiting (2000 req/5 min/IP), WAF logging to CloudWatch Logs. |
| **monitoring** | `modules/monitoring/` | Multi-region CloudTrail with CMK encryption and CloudWatch Logs integration, CloudWatch alarms (CPU >90%, status checks, unauthorized API calls), SNS alerting topic. |
| **security** | `modules/security/` | GuardDuty (with S3 log monitoring and malware protection for EBS volumes), Security Hub (NIST 800-53 v5 and AWS Foundational Security Best Practices), AWS Config (continuous configuration recording), Amazon Inspector (EC2 vulnerability scanning). |
| **lambda-user-deactivation** | `modules/lambda-user-deactivation/` | Python 3.12 Lambda function that deactivates GitLab accounts inactive for 90+ days. Runs weekly via EventBridge. Uses GitLab admin PAT from Secrets Manager. Sends notifications via SNS. Implements AC-2(3). |
| **rotation** | `modules/rotation/` | Python 3.12 Lambda function for automated GitLab root password rotation via Secrets Manager native rotation. Rotates every 90 days. Uses SSM Run Command to apply password on EC2. Implements IA-5(1). |
| **lambda-cisa-alerts** | `modules/lambda-cisa-alerts/` | Python 3.12 Lambda function that polls the CISA Known Exploited Vulnerabilities (KEV) catalog daily. Tracks state in DynamoDB. Sends new vulnerability alerts via SNS. Implements SI-5. |

### EC2 Instance Configuration

| Setting | Value |
|---|---|
| **AMI** | Amazon Linux 2023 (FIPS-validated AMI recommended) |
| **Instance Metadata** | IMDSv2 required (`http_tokens = "required"`) |
| **SSH Access** | Disabled; SSH daemon removed during bootstrap |
| **Admin Access** | SSM Session Manager only |
| **Antimalware** | ClamAV installed with daily scans and signature updates |
| **Monitoring Agent** | CloudWatch Agent (disk, memory metrics; ClamAV logs) |

---

## 4. System Interconnections

| # | External System | Direction | Protocol | Data Exchanged | Authorization |
|---|---|---|---|---|---|
| 1 | Route53 (parent zone) | Outbound (NS delegation) | DNS | NS records delegating subdomain | Parent zone in separate AWS account; not within authorization boundary |
| 2 | GitLab Package Repository (`packages.gitlab.com`) | Outbound | HTTPS | GitLab CE RPM packages and updates | Vendor-managed repository |
| 3 | ClamAV Signature Database (`database.clamav.net`) | Outbound | HTTPS | Malware signature updates (daily) | Open-source antimalware project |
| 4 | CISA KEV Catalog (`www.cisa.gov`) | Outbound | HTTPS | Known Exploited Vulnerabilities JSON feed (daily poll) | U.S. Government public data feed |
| 5 | AWS Services (via VPC Endpoints) | Bidirectional | HTTPS (private) | S3, SSM, Secrets Manager, CloudWatch Logs, KMS API calls | AWS FedRAMP High P-ATO |
| 6 | AWS Services (via NAT Gateway) | Outbound | HTTPS | CloudTrail, GuardDuty, Security Hub, Config, Inspector, SNS API calls | AWS FedRAMP High P-ATO |
| 7 | End-User Workstations | Inbound | HTTPS (TLS 1.3) | Web UI access, Git over HTTPS with PATs | User authentication (MFA + 15-char password) |
| 8 | Amazon Linux 2023 Repos | Outbound | HTTPS | OS package updates (`dnf`) | AWS-managed repository |

---

## 5. Laws, Regulations, and Policies

### Applicable Regulatory Framework

| Authority | Title | Applicability |
|---|---|---|
| DoD CC SRG | DoD Cloud Computing Security Requirements Guide (v1 R4) | Defines IL2 requirements; permits FedRAMP-authorized commercial cloud for IL2 |
| FedRAMP | Federal Risk and Authorization Management Program -- Moderate Baseline | Minimum baseline for IL2; AWS holds FedRAMP High P-ATO (exceeds requirement) |
| NIST SP 800-53 Rev 5 | Security and Privacy Controls for Information Systems and Organizations | Moderate baseline controls; mapped in the DoD IL2 compliance document |
| NIST SP 800-171 Rev 2 | Protecting Controlled Unclassified Information in Nonfederal Systems | Applicable if CUI is processed; 110 controls derived from 800-53 |
| NIST SP 800-18 Rev 1 | Guide for Developing Security Plans for Federal Information Systems | Defines the format for this SSP document |
| FISMA | Federal Information Security Modernization Act of 2014 | Mandates security plans, risk assessments, and continuous monitoring |
| FIPS 199 | Standards for Security Categorization of Federal Information | System categorized as Moderate (Confidentiality: Moderate, Integrity: Moderate, Availability: Moderate) |
| FIPS 140-2/3 | Security Requirements for Cryptographic Modules | FIPS-validated cryptographic modules recommended (FIPS AMI, AWS KMS uses FIPS 140-2 Level 3 HSMs) |
| DoDI 8510.01 | Risk Management Framework for DoD IT | Governs the ATO process for DoD systems |
| EO 14028 | Improving the Nation's Cybersecurity (2021) | Mandates zero trust, MFA, encryption, logging, and software supply chain security |

### IL2 Hosting Requirement Confirmation

| Requirement | Status | Evidence |
|---|---|---|
| FedRAMP Moderate or higher | Satisfied | AWS holds FedRAMP **High** P-ATO |
| GovCloud required | **No** | DoD CC SRG permits IL2 on FedRAMP-authorized commercial cloud |
| Data residency | US-only | All resources in selected US region; backups replicate to second US region |
| Encryption at rest | CMK | All data encrypted with Customer Managed KMS Keys |
| Encryption in transit | TLS 1.3 | ALB enforces `ELBSecurityPolicy-TLS13-1-2-2021-06` |

---

## 6. Security Control Summary

The full control-by-control implementation mapping is maintained in the companion document: [`dod-il2-compliance.md`](dod-il2-compliance.md). This section provides a summary by NIST 800-53 family.

### Control Implementation Status by Family

| NIST Family | Total Controls Addressed | Implemented | Partially Implemented | Gap | Key Implementations |
|---|---|---|---|---|---|
| **AC** -- Access Control | 7 | 7 | 0 | 0 | Admin-only accounts, WAF/SG enforcement, SSM-only access, MFA, DoD consent banner, inactive account deactivation (Lambda) |
| **AU** -- Audit and Accountability | 6 | 5 | 1 | 0 | CloudTrail (multi-region), VPC flow logs, ALB access logs, WAF logs, S3 access logs, 365-day retention |
| **CA** -- Security Assessment | 1 | 1 | 0 | 0 | GuardDuty, Security Hub (NIST 800-53 v5), AWS Config, Checkov IaC scanning |
| **CM** -- Configuration Management | 4 | 4 | 0 | 0 | Terraform IaC, Checkov policy enforcement, AWS Config drift detection, TLS 1.3, IMDSv2 |
| **CP** -- Contingency Planning | 3 | 2 | 1 | 0 | Daily S3 backups (CMK-encrypted), Secrets Manager backup, Terraform-based recovery, cross-region replication |
| **IA** -- Identification and Authentication | 5 | 5 | 0 | 0 | MFA (zero grace period), 15-char passwords, Secrets Manager, PAT auth, automated root password rotation (Lambda) |
| **IR** -- Incident Response | 3 | 3 | 0 | 0 | CloudWatch alarms, GuardDuty, Security Hub, formal IRP (docs/incident-response-plan.md) |
| **MP** -- Media Protection | 1 | 0 | 1 | 0 | `DataClassification=IL2` resource tagging; gap: FISMA System ID tags |
| **RA** -- Risk Assessment | 1 | 1 | 0 | 0 | Amazon Inspector (EC2 CVE scanning), Security Hub, GuardDuty, Checkov |
| **SC** -- System and Comms Protection | 6 | 6 | 0 | 0 | WAF rate limiting, private subnets, TLS 1.3, CMK encryption, VPC endpoints, FIPS AMI |
| **SI** -- System and Info Integrity | 5 | 5 | 0 | 0 | CloudWatch monitoring, GuardDuty, ClamAV antimalware, Amazon Inspector, CISA KEV monitoring (Lambda), AIDE file integrity monitoring |

### Overall Posture

- **Controls Implemented**: 39 of 42 addressed controls fully implemented
- **Partially Implemented**: 3 controls with identified enhancement paths (AU-6, CP-6, MP-3)
- **Gaps**: 0 infrastructure gaps; 2 procedural items tracked in [Remaining Gaps](#remaining-gaps) (AT-2 training, FISMA tags)

---

## 7. Minimum Security Controls

This section cross-references the NIST 800-53 Rev 5 Moderate baseline controls with the current implementation status. The full detail for each control is in [`dod-il2-compliance.md`](dod-il2-compliance.md).

### Implemented Controls

| Control | Title | Implementation Summary |
|---|---|---|
| AC-2 | Account Management | GitLab native auth, admin-only account creation, RBAC, root password in Secrets Manager |
| AC-2(3) | Inactive Accounts | Lambda function deactivates accounts inactive >90 days (weekly schedule via EventBridge) |
| AC-3 | Access Enforcement | Security groups (443 only), WAF filtering, least-privilege IAM, no SSH |
| AC-4 | Information Flow Enforcement | ALB + WAF + TLS 1.3, private subnets, NAT Gateway, VPC endpoints |
| AC-7 | Unsuccessful Logon Attempts | GitLab lockout + WAF rate limiting (2000 req/5 min/IP) |
| AC-8 | System Use Notification | DoD consent banner on GitLab sign-in page (`extra_sign_in_text` in `gitlab.rb`) |
| AC-17 | Remote Access | HTTPS with MFA + TLS 1.3; admin via SSM Session Manager; HTTPS-only Git (PATs) |
| AU-2 | Event Logging | CloudTrail, VPC flow logs, ALB logs, WAF logs, S3 access logs, GitLab audit events |
| AU-3 | Content of Audit Records | CloudTrail records (who, what, when, where, outcome); log file validation enabled |
| AU-9 | Protection of Audit Information | CMK-encrypted log buckets, public access blocked, versioning, CloudTrail log validation |
| AU-11 | Audit Record Retention | 365-day retention across all log stores; Glacier tiering at 30-90 days |
| AU-12 | Audit Record Generation | Automated generation across CloudTrail, flow logs, ALB, WAF, S3, AWS Config |
| CA-7 | Continuous Monitoring | GuardDuty (threat detection + malware protection), Security Hub (NIST 800-53 v5), AWS Config, Checkov |
| CM-2 | Baseline Configuration | Terraform IaC, AL2023 AMI, `user_data.sh` bootstrap, `gitlab.rb` template, AWS Config recording |
| CM-3 | Configuration Change Control | Terraform plan/apply, Checkov pre-deploy scanning, Git audit trail, AWS Config drift detection |
| CM-6 | Configuration Settings | TLS 1.3, IMDSv2, KMS key rotation, ALB header validation, GitLab hardening settings |
| CM-7 | Least Functionality | Port 443 only (ALB inbound and EC2 from ALB with self-signed TLS); SSH removed; HTTPS-only Git |
| CP-9 | System Backup | Daily GitLab data + config backups to S3 (CMK-encrypted, versioned, Glacier lifecycle) |
| CP-10 | System Recovery | Terraform rebuild, S3 backup restore, Secrets Manager recovery, separate data volume |
| IA-2 | Identification and Authentication | GitLab native auth, admin-managed accounts, signup disabled |
| IA-2(1) | MFA | TOTP required for all users, zero grace period |
| IA-5 | Authenticator Management | 15-char minimum passwords, Secrets Manager for root password, PAT-based Git auth |
| IA-5(1) | Authenticator Rotation | Automated Lambda-based root password rotation via Secrets Manager (90-day cycle) |
| IA-8 | Non-Organizational Users | Signup disabled, admin-only account creation, private defaults |
| IR-5 | Incident Monitoring | GuardDuty, Security Hub, CloudWatch alarms, WAF logging, CloudTrail + CloudWatch Logs |
| RA-5 | Vulnerability Scanning | Amazon Inspector (EC2 CVE scanning), Security Hub, GuardDuty, Checkov IaC scanning |
| SC-5 | Denial of Service Protection | WAF rate limiting, ALB load distribution, GitLab application rate limiting |
| SC-7 | Boundary Protection | Private subnets, WAF (OWASP + bad inputs), VPC endpoints, no public IP on EC2 |
| SC-8 | Transmission Confidentiality | TLS 1.3 at ALB, HTTPS for all user/Git traffic, VPC endpoints for AWS APIs |
| SC-12 | Cryptographic Key Management | 3 CMKs with annual rotation, ACM certificate management |
| SC-13 | Cryptographic Protection | FIPS-validated AMI recommended, TLS 1.3, CMK encryption, KMS FIPS 140-2 Level 3 HSMs |
| SC-28 | Protection of Information at Rest | CMK-encrypted EBS, S3, Secrets Manager; AES-256 for ALB logs; public access blocked |
| SI-2 | Flaw Remediation | Amazon Linux 2023 security updates via `dnf`, Amazon Inspector continuous CVE scanning, Security Hub integration |
| SI-3 | Malicious Code Protection | ClamAV on EC2 (daily scans, daily signature updates), GuardDuty malware protection (EBS volumes) |
| SI-4 | Information System Monitoring | CloudWatch (CPU, status, unauthorized API), CloudTrail, flow logs, WAF logs, GuardDuty, Security Hub, AWS Config |
| SI-5 | Security Alerts and Advisories | CISA KEV monitoring Lambda (daily), CloudWatch alarms via SNS, Security Hub findings |
| SI-7 | Software and Information Integrity | AIDE file integrity monitoring on EC2 (daily checks, results logged to CloudWatch) |

### Remaining Gaps

| Control | Title | Gap Description | Remediation Plan | Priority |
|---|---|---|---|---|
| AU-6 | Audit Review, Analysis, Reporting | No centralized SIEM for automated log correlation | Deploy Amazon OpenSearch or integrate with SIEM (Splunk, Elastic) | High |
| CP-6 | Alternate Storage Site | Cross-region replication configured but not verified | Validate replication resources are deployed and tested | Medium |
| MP-3 | Media Marking | No FISMA System ID or System Owner tags | Add FISMA tags to `default_tags` in Terraform provider | Low |
| AT-2 | Security Awareness Training | No formal training program | Establish annual training with documented completion records | Medium |

---

## 8. Personnel Security

### Roles and Responsibilities

| Role | Responsibilities | Minimum Clearance | Account Level |
|---|---|---|---|
| Authorizing Official (AO) | Accepts residual risk; issues ATO | _[Per org policy]_ | N/A |
| Information System Security Officer (ISSO) | Day-to-day security oversight, audit log review, incident coordination | _[Per org policy]_ | GitLab Admin |
| System Administrator | Infrastructure management, Terraform operations, patching, backup verification | _[Per org policy]_ | GitLab Admin + AWS IAM (SSM access) |
| Developer | Code development, merge requests, CI/CD pipeline usage | _[Per org policy]_ | GitLab Developer/Maintainer |
| Guest | Read-only access to selected projects | _[Per org policy]_ | GitLab Guest |

### Separation of Duties

- **Infrastructure changes** require Terraform plan review and explicit apply. Git history provides a full audit trail of who made what change and when.
- **GitLab admin operations** are limited to designated administrators. User account creation is restricted to admins (`gitlab_signup_enabled = false`).
- **AWS console/CLI access** is separate from GitLab application access. IAM policies follow least privilege. SSM Session Manager provides auditable admin access to EC2.
- **Secret access** is restricted via IAM policies and KMS key policies. Lambda functions have scoped permissions to only the secrets they require.

### Personnel Screening

- All personnel with privileged access must complete background investigation appropriate to the data classification (IL2) per organizational and DoD policies.
- Clearance levels must meet the minimum requirements defined by the Authorizing Official.
- Personnel changes (onboarding, offboarding, role changes) must be reflected in GitLab account provisioning within _[defined SLA]_.

### Access Termination

- Accounts are deactivated within _[defined SLA]_ of personnel departure.
- Automated deactivation of accounts inactive for 90+ days via Lambda function (AC-2(3)).
- SSM Session Manager access is revoked by removing IAM permissions.

---

## 9. Physical and Environmental Security

### AWS Shared Responsibility Model

Physical and environmental security for the underlying infrastructure is the responsibility of AWS under the AWS Shared Responsibility Model. AWS data centers meet the following standards:

| Control Area | AWS Responsibility | Evidence |
|---|---|---|
| PE-1 Physical Security Policy | AWS manages physical access policies for all data centers | FedRAMP High P-ATO; SOC 2 Type II |
| PE-2 Physical Access Authorizations | Multi-factor access control to data center floors | AWS FedRAMP SSP (available via FedRAMP PMO) |
| PE-3 Physical Access Control | Biometric readers, mantraps, 24/7 security staff, CCTV | AWS SOC 2 report |
| PE-6 Monitoring Physical Access | 90-day retention of access logs and CCTV | AWS compliance reports |
| PE-10 Emergency Shutoff | UPS, generators, automated shutoff systems | AWS infrastructure design |
| PE-11 Emergency Power | N+1 redundant power with diesel generator backup | AWS data center specifications |
| PE-12 Emergency Lighting | All data center facilities equipped | AWS compliance reports |
| PE-13 Fire Protection | Wet-pipe and pre-action sprinkler systems, VESDA detection | AWS SOC 2 report |
| PE-14 Environmental Controls | HVAC with continuous monitoring, temperature/humidity controls | AWS infrastructure design |
| PE-15 Water Damage Protection | Leak detection sensors with automated alerts | AWS data center operations |

### Customer Responsibility

The customer (system owner) is responsible for:

- **Logical access** to the EC2 instance and all AWS resources (implemented via IAM, security groups, WAF)
- **Data protection** at the application layer (implemented via GitLab settings, encryption, backups)
- **Secure configuration** of all deployed resources (implemented via Terraform IaC with Checkov scanning)

---

## 10. Contingency Planning

### Backup Strategy (CP-9)

| Backup Type | Frequency | Destination | Encryption | Retention |
|---|---|---|---|---|
| GitLab data backup (`gitlab-backup create`) | Daily (02:00 UTC) | S3 backup bucket | CMK | 365 days (30d to Glacier) |
| GitLab config backup (`/etc/gitlab/`) | Daily (02:15 UTC) | S3 backup bucket (`config-backups/` prefix) | CMK | 365 days (30d to Glacier) |
| `gitlab-secrets.json` | On initial deployment | AWS Secrets Manager | CMK | Indefinite |
| EBS data volume snapshots | Per AWS Backup schedule | Same region (EBS snapshots) | EBS CMK | _[Per backup policy]_ |
| S3 bucket versioning | Continuous | Same bucket (versioned objects) | CMK | Per lifecycle policy |
| Cross-region backup replication | Continuous (if enabled) | Secondary US region | CMK | Mirrors primary retention |

### Recovery Procedures (CP-10)

**Recovery Time Objective (RTO)**: _[To be defined by system owner]_
**Recovery Point Objective (RPO)**: 24 hours (daily backup cycle)

#### Full System Recovery Procedure

1. **Infrastructure Rebuild**: Execute `terraform apply` to recreate all AWS resources (VPC, EC2, ALB, WAF, security services, Lambda functions). Terraform state is stored in a versioned, encrypted S3 backend.
2. **Data Restoration**: Restore the latest GitLab data backup from S3 using `gitlab-backup restore`.
3. **Config Restoration**: Download the latest config backup from S3 and extract to `/etc/gitlab/`.
4. **Secrets Restoration**: Retrieve `gitlab-secrets.json` and root password from Secrets Manager.
5. **Reconfigure**: Run `gitlab-ctl reconfigure` to apply restored configuration.
6. **DNS Update**: Route53 alias record is managed by Terraform and updates automatically. Verify NS delegation in parent zone if hosted zone was recreated.
7. **Verification**: Confirm GitLab health check passes (`/-/health`), verify user access, and validate backup schedules are active.

#### Separate Data Volume

The GitLab data volume (`/var/opt/gitlab`) is a separate EBS volume from the root volume. This design allows:

- Independent data volume snapshots
- Data volume reattachment to a replacement instance
- Root volume replacement without data loss

### Accepted Risks (CP-2, CP-7)

| Risk | Rationale | Cost Avoidance |
|---|---|---|
| **Single NAT Gateway** -- NAT Gateway is deployed in one AZ only. If that AZ fails, private-subnet outbound internet access is lost. | The GitLab EC2 instance is also single-AZ, so a second NAT Gateway in a different AZ provides no high-availability benefit. The entire workload (EC2 + NAT) would need to be restored together. VPC endpoints (7 configured) provide continued private access to AWS services even if the NAT fails. | ~$32/month + data processing fees saved by not deploying a redundant NAT. |

### Contingency Plan Testing

- Contingency plan testing should be conducted _[annually / semi-annually]_ per organizational policy.
- Test scenarios should include: full Terraform rebuild, backup restoration, DNS failover, and Lambda function recovery.
- Test results must be documented and reviewed by the ISSO.

---

## 11. Configuration Management

### Infrastructure as Code (CM-2, CM-3)

All infrastructure is defined in Terraform HCL and maintained in a Git repository. No manual configuration is permitted outside of the Terraform workflow.

| Tool | Purpose | Implementation |
|---|---|---|
| **Terraform** (>= 1.5) | Infrastructure provisioning and management | All resources defined in `terraform/` directory with modular structure |
| **Checkov** | Static analysis / policy-as-code scanning | Pre-deploy scanning; all checks pass (skips documented with inline justifications) |
| **AWS Config** | Configuration drift detection and compliance recording | Continuous recording of all resource configurations (`modules/security/config.tf`) |
| **Git** | Change tracking and audit trail | All Terraform changes committed with author, timestamp, and description |

### Change Control Process

1. **Propose**: Developer creates a branch with Terraform changes.
2. **Scan**: Checkov runs against the proposed changes to enforce security policies.
3. **Review**: Changes reviewed via merge request (code review).
4. **Plan**: `terraform plan` executed to preview infrastructure changes.
5. **Approve**: Authorized personnel approve the plan output.
6. **Apply**: `terraform apply` executes the approved changes.
7. **Verify**: AWS Config confirms the applied state matches the expected configuration.
8. **Audit**: Git commit history and CloudTrail provide full audit trail.

### Baseline Configuration (CM-2)

| Component | Baseline Source | Verification |
|---|---|---|
| AWS infrastructure | Terraform modules and `main.tf` | `terraform plan` (drift detection) |
| EC2 instance | Amazon Linux 2023 AMI + `user_data.sh` bootstrap | AWS Config, CloudWatch Agent |
| GitLab application | `gitlab.rb` template in `user_data.sh` | GitLab admin panel, application logs |
| Security services | Terraform security module | Security Hub compliance dashboard |
| Network configuration | Terraform networking module | VPC flow logs, AWS Config |

### Configuration Settings (CM-6)

| Setting | Value | Enforcement |
|---|---|---|
| TLS minimum version | TLS 1.3 | ALB SSL policy `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| EC2 instance metadata | IMDSv2 required | `http_tokens = "required"` in Terraform |
| KMS key rotation | Automatic annual rotation | `enable_key_rotation = true` on all CMKs |
| ALB header validation | Drop invalid headers | `drop_invalid_header_fields = true` |
| GitLab signup | Disabled | `gitlab_signup_enabled = false` |
| MFA enforcement | Required, zero grace period | `require_two_factor_authentication = true` |
| Password minimum length | 15 characters | `password_minimum_length = 15` |
| Session timeout | 60 minutes | `session_expire_delay = 60` |
| Default visibility | Private (projects, groups, snippets) | `default_*_visibility = 'private'` |

---

## 12. Maintenance

### Patching Strategy

| Component | Update Method | Frequency | Responsibility |
|---|---|---|---|
| Amazon Linux 2023 (OS) | `dnf update --security` | Weekly (recommended) | System Administrator |
| GitLab CE | `dnf update gitlab-ce` or rebuild via Terraform | Monthly or per security advisory | System Administrator |
| Terraform providers | Update `.terraform.lock.hcl`, run `terraform init -upgrade` | Monthly | System Administrator |
| AWS managed services | Automatic (AWS responsibility) | Continuous | AWS |

### ClamAV Antimalware Updates (SI-3)

| Activity | Schedule | Configuration |
|---|---|---|
| Signature database update (`freshclam`) | Daily at 01:00 UTC | `/etc/cron.d/clamav-update` |
| Full scan of GitLab data directories | Daily at 03:00 UTC | `/etc/cron.d/clamav-scan` (targets `/var/opt/gitlab/git-data/` and `/var/opt/gitlab/uploads/`) |
| ClamAV scan logs to CloudWatch | Continuous | CloudWatch Agent config (`clamav-logs.json`) |
| `clamd` daemon | Continuous (systemd) | `clamd@scan` service enabled |

### Secret Rotation Schedule (IA-5(1))

| Secret | Rotation Method | Rotation Frequency | Implementation |
|---|---|---|---|
| GitLab root password | Automated Lambda via Secrets Manager native rotation | Every 90 days | `modules/rotation/main.tf` |
| GitLab admin PAT (for user deactivation Lambda) | Manual rotation via GitLab admin UI | Per organizational policy | Stored in Secrets Manager |
| KMS Customer Managed Keys | Automatic AWS KMS rotation | Annual | `enable_key_rotation = true` |
| ACM TLS certificate | Automatic renewal via ACM | Before expiration | ACM managed |

### Maintenance Windows

- Maintenance activities that require GitLab downtime (e.g., major version upgrades, data volume expansion) should be scheduled during defined maintenance windows.
- Maintenance window: _[To be defined by system owner, e.g., Sundays 02:00-06:00 UTC]_
- Emergency patches for critical vulnerabilities may be applied outside maintenance windows with ISSO approval.

---

## 13. System Integrity

### Vulnerability Scanning (RA-5, SI-2)

| Tool | Scope | Schedule | Output |
|---|---|---|---|
| **Amazon Inspector** | EC2 instance CVE scanning (OS and application packages) | Continuous (event-driven) | Findings in Security Hub |
| **Security Hub** | NIST 800-53 v5 and AWS Foundational Security Best Practices compliance checks | Continuous | Findings dashboard with severity scores |
| **Checkov** | Terraform IaC static analysis (misconfigurations, policy violations) | Pre-deploy (every change) | Pass/fail with inline skip justifications |
| **GuardDuty** | Threat detection (API anomalies, cryptocurrency mining, credential compromise) | Continuous | Findings in Security Hub |

### Antimalware Protection (SI-3)

| Layer | Tool | Capability |
|---|---|---|
| **Host-based** | ClamAV (on EC2) | Daily scans of GitLab data directories (`git-data/`, `uploads/`); daily signature updates; real-time daemon (`clamd`); logs to CloudWatch |
| **Cloud-based** | GuardDuty Malware Protection | Automated EBS volume scanning when GuardDuty detects suspicious activity; scans for trojans, rootkits, exploits |

### CISA KEV Monitoring (SI-5)

The `lambda-cisa-alerts` module implements automated monitoring of the CISA Known Exploited Vulnerabilities (KEV) catalog:

- **Frequency**: Daily at 06:00 UTC via EventBridge schedule
- **Data Source**: CISA KEV JSON feed (`https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json`)
- **State Tracking**: DynamoDB table tracks previously seen vulnerabilities to avoid duplicate alerts
- **Notification**: New KEV entries are published to the SNS alerting topic for administrator review
- **Encryption**: DynamoDB table encrypted with CMK; Lambda logs encrypted with CMK

### Continuous Monitoring Pipeline

```
[Amazon Inspector] --findings--> [Security Hub] --aggregation--> [Dashboard]
[GuardDuty]        --findings--> [Security Hub]
[AWS Config]       --findings--> [Security Hub]
[Checkov]          --pre-deploy scan--> [Git CI/CD]

[CloudTrail]       --API logs-->  [CloudWatch Logs] --alarms--> [SNS] --notify--> [Admin]
[VPC Flow Logs]    --traffic-->   [CloudWatch Logs]
[WAF Logs]         --requests-->  [CloudWatch Logs]
[ClamAV Logs]      --scan results--> [CloudWatch Logs]

[CISA KEV Lambda]  --new vulns--> [SNS] --notify--> [Admin]
[User Deact Lambda] --deactivations--> [SNS] --notify--> [Admin]
```

---

## 14. Plan Approval and Authorization

### Document Approval

This System Security Plan has been reviewed and approved by the following officials:

#### System Owner

| Field | Value |
|---|---|
| Name | ___________________________ |
| Title | ___________________________ |
| Organization | ___________________________ |
| Signature | ___________________________ |
| Date | ___________________________ |

#### Information System Security Officer (ISSO)

| Field | Value |
|---|---|
| Name | ___________________________ |
| Title | ___________________________ |
| Organization | ___________________________ |
| Signature | ___________________________ |
| Date | ___________________________ |

#### Authorizing Official (AO)

| Field | Value |
|---|---|
| Name | ___________________________ |
| Title | ___________________________ |
| Organization | ___________________________ |
| Signature | ___________________________ |
| Date | ___________________________ |

### Authorization to Operate (ATO)

| Field | Value |
|---|---|
| **ATO Type** | _[Full ATO / Interim ATO / ATO with Conditions]_ |
| **ATO Date** | _[Date issued]_ |
| **ATO Expiration** | _[Date -- typically 3 years from issuance]_ |
| **Conditions** | _[Any conditions imposed by the AO]_ |
| **Risk Acceptance** | The AO accepts the residual risks documented in the [Residual Gaps](#remaining-gaps) section of this SSP and the companion [DoD IL2 Compliance Mapping](dod-il2-compliance.md). |

### ATO Process Reference

The ATO process follows DoDI 8510.01 (Risk Management Framework for DoD IT):

1. **Categorize** -- System categorized as Moderate per FIPS 199 / CNSSI 1253
2. **Select** -- NIST 800-53 Rev 5 Moderate baseline controls selected
3. **Implement** -- Controls implemented via Terraform IaC (documented in this SSP and `dod-il2-compliance.md`)
4. **Assess** -- Independent security assessment by qualified assessor (SCA)
5. **Authorize** -- AO reviews assessment results, accepts residual risk, issues ATO
6. **Monitor** -- Continuous monitoring via GuardDuty, Security Hub, AWS Config, Inspector, CISA KEV Lambda

### Document Revision History

| Version | Date | Author | Description |
|---|---|---|---|
| 1.0 | 2026-03-03 | _[Author]_ | Initial SSP based on NIST 800-18 Rev 1 format |

---

*This System Security Plan is a living document and must be reviewed and updated at least annually or when significant changes occur to the system architecture, security posture, or authorization boundary. Changes to security controls must be reflected in both this SSP and the companion [DoD IL2 Compliance Mapping](dod-il2-compliance.md).*
