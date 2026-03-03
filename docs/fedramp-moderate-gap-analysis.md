# FedRAMP Moderate Gap Analysis — Air-Gapped GitLab CE on AWS

**Date:** 2026-03-03
**System:** GitLab CE on AWS (private subnet, Tailscale VPN, Google OAuth)
**Baseline:** FedRAMP Moderate (NIST SP 800-53 Rev 5)
**Shared Responsibility:** AWS handles physical/infrastructure controls; this analysis covers customer-responsible controls.

## Summary

| Status | Count | Description |
|--------|-------|-------------|
| Implemented | 68 | Fully addressed by infrastructure, GitLab config, or AWS services |
| Partially Implemented | 45 | Technical controls in place, needs policy/procedural documentation |
| Gap | 32 | Requires additional tooling, policy, or procedural controls |
| N/A / AWS Responsibility | 40 | Handled by AWS under shared responsibility model |

---

## AC — Access Control

### AC-1: Access Control Policy and Procedures
- **Status:** Gap
- **Type:** Policy
- **Evidence:** Technical controls implemented but no formal policy document
- **Remediation:** Draft access control policy referencing GitLab RBAC, Tailscale VPN, Google OAuth

### AC-2: Account Management
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** Google OAuth auto-provisions accounts, GitLab admin can manage users, IAM roles defined in Terraform (`modules/gitlab/iam.tf`)
- **Remediation:** Document account lifecycle procedures (provisioning, review, deprovisioning); implement 90-day inactive account deactivation

### AC-3: Access Enforcement
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab RBAC enforces project/group permissions, IAM policies enforce AWS access, security groups enforce network access (`modules/networking/security_groups.tf`)

### AC-4: Information Flow Enforcement
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** VPC with private subnets, security groups, NAT Gateway for controlled outbound, VPC endpoints for AWS services (`modules/networking/endpoints.tf`), `allow_local_requests_from_web_hooks_and_services = false`

### AC-5: Separation of Duties
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** GitLab Owner/Maintainer/Developer role separation, separate AWS accounts for DNS
- **Remediation:** Document separation of duties matrix

### AC-6: Least Privilege
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** IAM role with scoped policies (`modules/gitlab/iam.tf`), security groups with minimal ports, GitLab default visibility private

### AC-7: Unsuccessful Logon Attempts
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab rate limiting (`rate_limiting_enabled = true`), Google OAuth handles login attempts

### AC-8: System Use Notification
- **Status:** Gap
- **Type:** Configuration
- **Evidence:** No login banner configured
- **Remediation:** Configure GitLab sign-in page banner (Admin > Appearance)

### AC-10: Concurrent Session Control
- **Status:** Partially Implemented
- **Type:** Configuration
- **Evidence:** GitLab session management active, session timeout at 480 minutes
- **Remediation:** Configure maximum concurrent sessions per user in GitLab

### AC-11: Device Lock
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Session timeout configured (`session_expire_delay = 480`)

### AC-12: Session Termination
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab session expiration, ALB connection timeouts

### AC-14: Permitted Actions Without Identification
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** No anonymous access; signup disabled, all actions require authentication

### AC-17: Remote Access
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Tailscale VPN required, ALB internal only, TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), VPC Flow Logs monitor all connections

### AC-18: Wireless Access
- **Status:** N/A (AWS Responsibility)

### AC-19: Access Control for Mobile Devices
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Tailscale device authorization
- **Remediation:** Document mobile device access policy

### AC-20: Use of External Systems
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Outbound webhooks disabled, Gravatar disabled
- **Remediation:** Document policy for external system connections

### AC-21: Information Sharing
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Default project visibility set to private
- **Remediation:** Document information sharing procedures and approval process

### AC-22: Publicly Accessible Content
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** No public-facing endpoints, all defaults set to private visibility

---

## AU — Audit and Accountability

### AU-1: Audit and Accountability Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft audit policy referencing CloudTrail, VPC Flow Logs, ALB logs, GitLab audit events

### AU-2: Event Logging
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** CloudTrail (`modules/monitoring/cloudtrail.tf`), VPC Flow Logs (`modules/networking/flow_logs.tf`), ALB access logs (`modules/alb/logging.tf`), GitLab audit events

### AU-3: Content of Audit Records
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** CloudTrail includes who/what/when/where/outcome, VPC Flow Logs include source/dest/port/action, GitLab audit logs include user/action/target

### AU-4: Audit Log Storage Capacity
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** S3 with unlimited storage, lifecycle policies for Glacier transition and expiration (30d/365d for flow logs, 90d/365d for CloudTrail)

### AU-5: Response to Audit Processing Failures
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** CloudWatch status check alarms (`modules/monitoring/cloudwatch.tf`)
- **Remediation:** Add CloudWatch alarm for CloudTrail delivery failures; add SNS notification

### AU-6: Audit Record Review, Analysis, and Reporting
- **Status:** Gap
- **Type:** Procedural
- **Evidence:** Logs stored in S3 but no review process
- **Remediation:** Implement regular log review procedures; consider CloudWatch Logs Insights or SIEM integration

### AU-7: Audit Record Reduction and Report Generation
- **Status:** Gap
- **Type:** Tooling
- **Remediation:** Implement log query/reporting capability (CloudWatch Logs Insights, Athena, or third-party)

### AU-8: Time Stamps
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** EC2 uses Amazon Time Sync Service, all AWS services use synchronized UTC timestamps

### AU-9: Protection of Audit Information
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** S3 buckets encrypted with KMS, public access blocked, bucket policies restrict writes to service principals, separate log buckets with IAM-restricted access

### AU-11: Audit Record Retention
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** S3 lifecycle policies retain logs (365 days active, Glacier archive before deletion)

### AU-12: Audit Record Generation
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** CloudTrail enabled for all management events, VPC Flow Logs on VPC, ALB access logging enabled

---

## CA — Assessment, Authorization, and Monitoring

### CA-1: Assessment, Authorization, and Monitoring Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft security assessment policy

### CA-2: Control Assessments
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** This gap analysis, Checkov automated scanning
- **Remediation:** Schedule annual security control assessments with documented results

### CA-3: Information Exchange
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Cross-account DNS via IAM role assumption (`modules/main.tf` — `dns_account` provider)
- **Remediation:** Document interconnection security agreements (ISAs)

### CA-5: Plan of Action and Milestones
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Create formal POA&M from this gap analysis

### CA-6: Authorization
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Obtain formal Authorization to Operate (ATO) before processing CUI

### CA-7: Continuous Monitoring
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** CloudWatch alarms, CloudTrail, VPC Flow Logs
- **Remediation:** Implement continuous monitoring strategy document; add automated alerting

### CA-9: Internal System Connections
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** VPC endpoints for internal AWS service communication, documented in Terraform

---

## CM — Configuration Management

### CM-1: Configuration Management Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft configuration management policy referencing Terraform IaC

### CM-2: Baseline Configuration
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Terraform modules define infrastructure baseline, `gitlab.rb` in `user_data.sh` defines application baseline, Amazon Linux 2023 as OS baseline

### CM-3: Configuration Change Control
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** Terraform state tracks changes, `terraform plan` shows impact, git history tracks code changes
- **Remediation:** Document change control board process; require `terraform plan` review before apply

### CM-4: Impact Analyses
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** `terraform plan` shows change impact, Checkov scans security implications
- **Remediation:** Document security impact analysis process for changes

### CM-5: Access Restrictions for Change
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Terraform state in S3 with DynamoDB locking, IAM restricts who can run Terraform, SSM restricts EC2 access

### CM-6: Configuration Settings
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Checkov enforces security settings (`.checkov.yml`), Terraform validates configuration, hardened `gitlab.rb` settings

### CM-7: Least Functionality
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Minimal security group rules, only required VPC endpoints, GitLab signup/Gravatar/webhooks disabled, minimal OS packages in `user_data.sh`

### CM-8: System Component Inventory
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** Terraform state provides infrastructure inventory, GitLab tracks its own components
- **Remediation:** Document complete system component inventory including software versions

### CM-9: Configuration Management Plan
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Document configuration management plan referencing Terraform workflow

### CM-10: Software Usage Restrictions
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Only approved packages installed via `user_data.sh`
- **Remediation:** Document approved software list

### CM-11: User-Installed Software
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** No SSH keys deployed, SSM access requires IAM
- **Remediation:** Document policy restricting software installation

---

## CP — Contingency Planning

### CP-1: Contingency Planning Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft contingency planning policy

### CP-2: Contingency Plan
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Develop contingency plan including backup restoration procedures

### CP-3: Contingency Training
- **Status:** Gap
- **Type:** Organizational
- **Remediation:** Schedule contingency training for operations team

### CP-4: Contingency Plan Testing
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Schedule annual contingency plan testing including backup restoration drill

### CP-6: Alternate Storage Site
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** S3 backup bucket with Glacier lifecycle (`modules/gitlab/backup.tf`), `backup_replication_region` variable defined for cross-region replication
- **Remediation:** Implement S3 cross-region replication for backups

### CP-7: Alternate Processing Site
- **Status:** Gap
- **Type:** Infrastructure
- **Remediation:** Document recovery procedure for deploying GitLab in alternate region using Terraform

### CP-9: System Backup
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Daily GitLab backup cron (`user_data.sh`), config backup, S3 upload with IAM role, backup retention (7 days local, 365 days S3), Glacier archival

### CP-10: System Recovery and Reconstitution
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** Terraform enables infrastructure recreation, backups enable data recovery
- **Remediation:** Document and test full recovery procedure (RTO/RPO targets)

---

## IA — Identification and Authentication

### IA-1: Identification and Authentication Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft I&A policy referencing Google OAuth, SSH keys, PATs

### IA-2: Identification and Authentication (Organizational Users)
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Google OAuth with domain restriction, unique user identities, MFA via Google Workspace

### IA-3: Device Identification and Authentication
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** Tailscale identifies devices, EC2 instance profile authenticates to AWS
- **Remediation:** Document device authentication requirements

### IA-4: Identifier Management
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Google OAuth provides unique identifiers, GitLab enforces unique usernames, AWS IAM provides unique ARNs

### IA-5: Authenticator Management
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** Secrets Manager stores credentials (`modules/gitlab/secrets.tf`), SSH keys user-managed, PATs have expiration
- **Remediation:** Document authenticator management procedures including rotation schedules

### IA-6: Authentication Feedback
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab obscures password input, OAuth redirects don't expose credentials

### IA-7: Cryptographic Module Authentication
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** FIPS mode attempted in `user_data.sh`, AWS KMS uses FIPS 140-2 validated HSMs
- **Remediation:** Verify FIPS mode is active post-boot; use FIPS-validated AMI

### IA-8: Identification and Authentication (Non-Organizational Users)
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Signup disabled, Google OAuth restricted to organization domain (`google_oauth_hd`), no anonymous access

---

## IR — Incident Response

### IR-1: Incident Response Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft incident response policy and procedures

### IR-2: Incident Response Training
- **Status:** Gap
- **Type:** Organizational
- **Remediation:** Develop and deliver incident response training

### IR-3: Incident Response Testing
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Schedule annual incident response exercises

### IR-4: Incident Handling
- **Status:** Gap
- **Type:** Procedural
- **Evidence:** Logging infrastructure exists for forensics
- **Remediation:** Document incident handling procedures (detection, analysis, containment, eradication, recovery)

### IR-5: Incident Monitoring
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** CloudTrail, VPC Flow Logs, CloudWatch alarms provide monitoring data
- **Remediation:** Implement alerting for security-relevant events

### IR-6: Incident Reporting
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Document incident reporting procedures and contacts

### IR-7: Incident Response Assistance
- **Status:** Gap
- **Type:** Organizational
- **Remediation:** Establish incident response support contacts and escalation paths

### IR-8: Incident Response Plan
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Develop comprehensive incident response plan

---

## MA — Maintenance

### MA-1: Maintenance Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft system maintenance policy

### MA-2: Controlled Maintenance
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** SSM Session Manager for controlled access, CloudTrail logs all actions
- **Remediation:** Document maintenance procedures and schedules

### MA-3: Maintenance Tools
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** SSM provides controlled tool access, no SSH keys deployed
- **Remediation:** Document approved maintenance tools

### MA-4: Non-Local Maintenance
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** SSM Session Manager with IAM authentication, all sessions logged, Tailscale provides encrypted tunnel

### MA-5: Maintenance Personnel
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Document authorized maintenance personnel and authorization procedures

---

## MP — Media Protection

### MP-1: Media Protection Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft media protection policy

### MP-2: Media Access
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** IAM policies restrict S3/EBS access, encrypted volumes

### MP-3: Media Marking
- **Status:** Gap
- **Type:** Configuration
- **Remediation:** Add CUI marking tags to all S3 buckets and EBS volumes

### MP-4: Media Storage
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** S3 with KMS encryption, EBS encrypted, public access blocked

### MP-5: Media Transport
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** TLS 1.3, WireGuard (Tailscale), SSH — all data encrypted in transit

### MP-6: Media Sanitization
- **Status:** Implemented (AWS Responsibility)
- **Type:** Infrastructure
- **Evidence:** AWS handles physical media destruction, EBS encryption ensures cryptographic erasure

### MP-7: Media Use
- **Status:** N/A
- **Evidence:** Cloud-based, no removable media

---

## PE — Physical and Environmental Protection

All PE controls (PE-1 through PE-17) are **N/A — AWS Responsibility** under the shared responsibility model. AWS maintains SOC 2, ISO 27001, and FedRAMP High certifications for physical infrastructure.

---

## PL — Planning

### PL-1: Planning Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft security planning policy

### PL-2: System Security and Privacy Plans
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Design document, this gap analysis
- **Remediation:** Develop formal System Security Plan (SSP)

### PL-4: Rules of Behavior
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft acceptable use policy / rules of behavior for GitLab users

---

## PS — Personnel Security

### PS-1: Personnel Security Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft personnel security policy

### PS-2: Position Risk Designation
- **Status:** Gap
- **Type:** Organizational
- **Remediation:** Categorize positions by risk level

### PS-3: Personnel Screening
- **Status:** Gap
- **Type:** Organizational
- **Remediation:** Implement background screening for CUI-accessing personnel

### PS-4: Personnel Termination
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Google OAuth can be centrally disabled, Tailscale device removal
- **Remediation:** Document offboarding checklist (Google account, Tailscale, GitLab, PATs, SSH keys)

### PS-5: Personnel Transfer
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Document access review procedures for role changes

### PS-6: Access Agreements
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft access agreements for CUI system users

### PS-7: External Personnel Security
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Document third-party access requirements

---

## RA — Risk Assessment

### RA-1: Risk Assessment Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft risk assessment policy

### RA-2: Security Categorization
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** System categorized as Moderate per FedRAMP
- **Remediation:** Complete FIPS 199 categorization document

### RA-3: Risk Assessment
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** This gap analysis, Checkov automated scanning
- **Remediation:** Conduct formal risk assessment and document results

### RA-5: Vulnerability Monitoring and Scanning
- **Status:** Partially Implemented
- **Type:** Infrastructure + Procedural
- **Evidence:** Checkov scans Terraform
- **Remediation:** Enable Amazon Inspector for EC2; implement periodic GitLab vulnerability scanning; document remediation SLAs

---

## SA — System and Services Acquisition

### SA-1: System and Services Acquisition Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft acquisition policy

### SA-2: Allocation of Resources
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** EC2 instance sizing defined in variables, EBS volume sizing configured
- **Remediation:** Document resource allocation decisions

### SA-3: System Development Life Cycle
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Terraform IaC with version control, Checkov security scanning
- **Remediation:** Document SDLC process for infrastructure changes

### SA-4: Acquisition Process
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Open-source GitLab CE, AWS services with FedRAMP authorization
- **Remediation:** Document vendor security requirements

### SA-5: System Documentation
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Design document, this gap analysis, quick-start guide, Terraform code as documentation
- **Remediation:** Create administrator guide and security architecture document

### SA-9: External System Services
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** AWS (FedRAMP authorized), Google OAuth, Tailscale
- **Remediation:** Document external service dependencies and security responsibilities

---

## SC — System and Communications Protection

### SC-1: System and Communications Protection Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft SC policy

### SC-5: Denial-of-Service Protection
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** Internal ALB (no public exposure), rate limiting in GitLab, security groups
- **Remediation:** Consider AWS Shield Standard (included) documentation

### SC-7: Boundary Protection
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** VPC with public/private subnets, security groups, NAT Gateway, VPC endpoints, internal ALB, Tailscale VPN

### SC-8: Transmission Confidentiality and Integrity
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** TLS 1.3 on ALB, WireGuard via Tailscale, SSH for Git, HTTPS for OAuth

### SC-10: Network Disconnect
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Session timeouts configured (GitLab 480min, ALB idle timeout)

### SC-12: Cryptographic Key Establishment and Management
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** AWS KMS manages encryption keys, ACM manages TLS certificates
- **Remediation:** Document key management lifecycle procedures

### SC-13: Cryptographic Protection
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** FIPS mode setup attempted, AWS KMS FIPS 140-2 validated, TLS 1.3
- **Remediation:** Verify FIPS mode active; document cryptographic mechanisms in use

### SC-15: Collaborative Computing Devices and Applications
- **Status:** N/A
- **Evidence:** No collaborative computing devices

### SC-17: Public Key Infrastructure Certificates
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** ACM certificate with DNS validation (`modules/alb/acm.tf`), cross-account Route 53 validation

### SC-18: Mobile Code
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** No CI/CD runners deployed
- **Remediation:** Document mobile code policy for future CI/CD runner deployment

### SC-20: Secure Name/Address Resolution Service
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Route 53 private hosted zone (`modules/dns/route53.tf`), VPC DNS resolution enabled

### SC-21: Secure Name/Address Resolution Service (Recursive or Caching Resolver)
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** VPC DNS resolver (Amazon-provided DNS)

### SC-22: Architecture and Provisioning for Name/Address Resolution Service
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** Route 53 provides fault-tolerant DNS

### SC-28: Protection of Information at Rest
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** EBS encrypted (`modules/gitlab/ec2.tf`), S3 KMS encryption, Secrets Manager encrypted, DynamoDB encrypted

### SC-39: Process Isolation
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** EC2 provides hardware-level isolation, GitLab runs as separate processes, private VPC provides network isolation

---

## SI — System and Information Integrity

### SI-1: System and Information Integrity Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft SI policy

### SI-2: Flaw Remediation
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Amazon Linux 2023 security updates, GitLab patches available
- **Remediation:** Document patching schedule and SLAs; configure `dnf-automatic`

### SI-3: Malicious Code Protection
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** Amazon Linux 2023 security features
- **Remediation:** Enable SELinux enforcing; consider ClamAV for Git push scanning

### SI-4: System Monitoring
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** CloudWatch alarms (`modules/monitoring/cloudwatch.tf`), CloudTrail, VPC Flow Logs, ALB access logs, CloudWatch agent for disk/memory metrics (`user_data.sh`)

### SI-5: Security Alerts, Advisories, and Directives
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Subscribe to GitLab security alerts, AWS Security Bulletins, Amazon Linux advisories

### SI-7: Software, Firmware, and Information Integrity
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** CloudTrail log file validation enabled (`enable_log_file_validation = true`), Terraform state integrity
- **Remediation:** Consider AIDE file integrity monitoring on EC2

### SI-10: Information Input Validation
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab handles input validation, Terraform validates configuration

### SI-11: Error Handling
- **Status:** Implemented
- **Type:** Infrastructure
- **Evidence:** GitLab handles errors without exposing sensitive data, custom error pages

### SI-12: Information Management and Retention
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** S3 lifecycle policies define retention periods (flow logs 365d, CloudTrail 365d, backups 365d)
- **Remediation:** Document information retention policy aligned with organizational requirements

### SI-16: Memory Protection
- **Status:** Implemented (OS Level)
- **Type:** Infrastructure
- **Evidence:** Amazon Linux 2023 includes ASLR, NX/XD, stack protection

---

## SR — Supply Chain Risk Management

### SR-1: Supply Chain Risk Management Policy
- **Status:** Gap
- **Type:** Policy
- **Remediation:** Draft supply chain risk management policy

### SR-2: Supply Chain Risk Assessment
- **Status:** Partially Implemented
- **Type:** Procedural
- **Evidence:** Using AWS (FedRAMP authorized), open-source GitLab CE (auditable)
- **Remediation:** Document supply chain risk assessment for all components

### SR-3: Supply Chain Controls and Processes
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** Terraform version-pinned providers, GitLab installed from official repos
- **Remediation:** Document software supply chain verification procedures

### SR-5: Acquisition Strategies, Tools, and Methods
- **Status:** Gap
- **Type:** Procedural
- **Remediation:** Document acquisition security requirements

### SR-11: Component Authenticity
- **Status:** Partially Implemented
- **Type:** Infrastructure
- **Evidence:** AWS AMIs are signed, GitLab packages signed by GitLab Inc., Terraform providers signed by HashiCorp
- **Remediation:** Document component authenticity verification procedures

---

## Key Remediation Priorities

### Immediate (Required for ATO)
1. Draft System Security Plan (SSP)
2. Complete POA&M from this analysis
3. Implement login banner (AC-8)
4. Configure inactive account deactivation (AC-2)
5. Obtain formal Authorization to Operate

### Short-Term (30-60 days)
1. Draft required policies (AC-1, AU-1, CM-1, IR-1, etc.)
2. Enable Amazon Inspector for vulnerability scanning
3. Implement log analysis/SIEM capability
4. Document incident response procedures
5. Configure SELinux enforcing mode

### Medium-Term (60-180 days)
1. Develop security awareness training
2. Conduct incident response exercises
3. Implement continuous monitoring dashboard
4. Complete contingency plan and testing
5. Implement S3 cross-region replication for backups
