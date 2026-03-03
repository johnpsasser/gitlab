# CMMC Level 2 Gap Analysis — Air-Gapped GitLab CE on AWS

**Date:** 2026-03-03
**System:** GitLab CE on AWS (private subnet, Tailscale VPN, Google OAuth)
**Baseline:** CMMC Level 2 (110 practices mapping to NIST SP 800-171 Rev 2)

## Summary

| Status | Count | Description |
|--------|-------|-------------|
| Implemented | 42 | Fully addressed by infrastructure or GitLab configuration |
| Partially Implemented | 31 | Technical controls in place, policy/procedural documentation needed |
| Gap | 18 | Requires additional tooling, policy, or procedural controls |
| N/A or Organizational | 19 | Outside system boundary (physical, personnel, training) |

---

## Access Control (AC) — 22 Practices

### AC.L2-3.1.1 — Limit system access to authorized users
- **Status:** Implemented
- **Evidence:** Google OAuth with domain restriction (`google_oauth_hd` in `gitlab.rb`), Tailscale VPN mesh required for network access, internal ALB (`modules/alb/alb.tf` — `internal = true`), private subnets only
- **Remediation:** None

### AC.L2-3.1.2 — Limit system access to authorized transactions and functions
- **Status:** Implemented
- **Evidence:** GitLab RBAC (Owner/Maintainer/Developer/Reporter/Guest roles), IAM least-privilege policies (`modules/gitlab/iam.tf`), security groups restrict ports (`modules/networking/security_groups.tf`)
- **Remediation:** None

### AC.L2-3.1.3 — Control CUI flow
- **Status:** Partially Implemented
- **Evidence:** Private VPC with no public endpoints, VPC endpoints for AWS services (`modules/networking/endpoints.tf`), ALB internal only, all traffic via Tailscale VPN
- **Remediation:** Document data flow diagrams showing CUI boundaries

### AC.L2-3.1.4 — Separate duties to reduce risk
- **Status:** Partially Implemented
- **Evidence:** GitLab role-based access (separate Owner/Maintainer roles), separate AWS accounts for DNS
- **Remediation:** Document separation of duties policy; implement protected branches requiring different approver than author

### AC.L2-3.1.5 — Employ least privilege
- **Status:** Implemented
- **Evidence:** IAM role with scoped policies (`modules/gitlab/iam.tf`), Secrets Manager access limited to `gitlab/*` prefix, S3 access limited to backup bucket pattern, security groups with minimal port exposure
- **Remediation:** None

### AC.L2-3.1.6 — Use non-privileged accounts for non-security functions
- **Status:** Partially Implemented
- **Evidence:** EC2 instance uses IAM role (not root credentials), GitLab admin vs. regular user separation
- **Remediation:** Document procedure for using separate admin accounts for GitLab administration

### AC.L2-3.1.7 — Prevent non-privileged users from executing privileged functions
- **Status:** Implemented
- **Evidence:** GitLab Admin area restricted to admin users, AWS IAM prevents unauthorized API calls, SSM Session Manager requires IAM permissions, IMDSv2 enforced (`modules/gitlab/ec2.tf`)
- **Remediation:** None

### AC.L2-3.1.8 — Limit unsuccessful logon attempts
- **Status:** Implemented
- **Evidence:** GitLab rate limiting enabled (`gitlab.rb` — `rate_limiting_enabled = true`), throttle settings configured for API requests
- **Remediation:** None

### AC.L2-3.1.9 — Provide privacy and security notices
- **Status:** Gap
- **Evidence:** None
- **Remediation:** Configure GitLab login banner via Admin > Appearance > Sign-in page text

### AC.L2-3.1.10 — Use session lock after inactivity
- **Status:** Implemented
- **Evidence:** GitLab session timeout set to 480 minutes (`gitlab.rb` — `session_expire_delay = 480`)
- **Remediation:** Consider reducing to 30 minutes for CUI systems

### AC.L2-3.1.11 — Terminate sessions after defined conditions
- **Status:** Implemented
- **Evidence:** GitLab session expiration configured, HTTPS listener with ALB handling connection termination
- **Remediation:** None

### AC.L2-3.1.12 — Monitor and control remote access
- **Status:** Implemented
- **Evidence:** All access via Tailscale VPN (logged), VPC Flow Logs capture all traffic (`modules/networking/flow_logs.tf`), CloudTrail logs API calls (`modules/monitoring/cloudtrail.tf`)
- **Remediation:** None

### AC.L2-3.1.13 — Employ cryptographic mechanisms for remote access
- **Status:** Implemented
- **Evidence:** TLS 1.3 on ALB (`ELBSecurityPolicy-TLS13-1-2-2021-06` in `modules/alb/alb.tf`), Tailscale WireGuard encryption, SSH for Git operations
- **Remediation:** None

### AC.L2-3.1.14 — Route remote access via managed access control points
- **Status:** Implemented
- **Evidence:** All traffic routed through ALB in private subnet, Tailscale acts as managed VPN gateway, no direct internet exposure
- **Remediation:** None

### AC.L2-3.1.15 — Authorize remote execution of privileged commands
- **Status:** Partially Implemented
- **Evidence:** SSM Session Manager requires IAM authorization, GitLab admin actions logged
- **Remediation:** Document authorized remote administration procedures

### AC.L2-3.1.16 — Authorize wireless access
- **Status:** N/A
- **Evidence:** Cloud-based system, no wireless infrastructure managed
- **Remediation:** None

### AC.L2-3.1.17 — Protect wireless access using authentication and encryption
- **Status:** N/A
- **Evidence:** Cloud-based system
- **Remediation:** None

### AC.L2-3.1.18 — Control connection of mobile devices
- **Status:** Partially Implemented
- **Evidence:** Tailscale device authorization controls which devices can connect
- **Remediation:** Document mobile device policy for Tailscale-connected devices

### AC.L2-3.1.19 — Encrypt CUI on mobile devices
- **Status:** Partially Implemented
- **Evidence:** All data encrypted in transit (TLS 1.3, WireGuard), data at rest encrypted (EBS, S3 KMS)
- **Remediation:** Document mobile device encryption requirements

### AC.L2-3.1.20 — Verify and control connections to external systems
- **Status:** Implemented
- **Evidence:** Security groups restrict outbound to HTTPS/HTTP/DNS only (`modules/networking/security_groups.tf`), NAT Gateway for controlled outbound, `allow_local_requests_from_web_hooks_and_services = false` in `gitlab.rb`
- **Remediation:** None

### AC.L2-3.1.21 — Limit use of portable storage devices
- **Status:** Gap
- **Evidence:** None (EC2-based, no physical USB concern, but policy needed)
- **Remediation:** Document policy prohibiting CUI transfer via unauthorized portable media

### AC.L2-3.1.22 — Control CUI posted or processed on publicly accessible systems
- **Status:** Implemented
- **Evidence:** No public endpoints, all GitLab defaults set to private (`default_project_visibility = 'private'` in `gitlab.rb`), signup disabled
- **Remediation:** None

---

## Awareness and Training (AT) — 3 Practices

### AT.L2-3.2.1 — Ensure personnel are aware of security risks
- **Status:** Gap (Organizational)
- **Evidence:** None
- **Remediation:** Develop security awareness training program covering CUI handling

### AT.L2-3.2.2 — Ensure personnel are trained in duties
- **Status:** Gap (Organizational)
- **Evidence:** None
- **Remediation:** Develop role-based security training for GitLab administrators and developers

### AT.L2-3.2.3 — Provide awareness of insider threat indicators
- **Status:** Gap (Organizational)
- **Evidence:** None
- **Remediation:** Include insider threat awareness in security training program

---

## Audit and Accountability (AU) — 9 Practices

### AU.L2-3.3.1 — Create and retain audit logs
- **Status:** Implemented
- **Evidence:** CloudTrail (`modules/monitoring/cloudtrail.tf`), VPC Flow Logs (`modules/networking/flow_logs.tf`), ALB access logs (`modules/alb/logging.tf`), GitLab built-in audit events
- **Remediation:** None

### AU.L2-3.3.2 — Ensure actions are traceable to individual users
- **Status:** Implemented
- **Evidence:** Google OAuth provides unique user identity, GitLab audit logs include user attribution, CloudTrail logs include IAM identity
- **Remediation:** None

### AU.L2-3.3.3 — Review and update audit events
- **Status:** Partially Implemented
- **Evidence:** Audit logging configured for infrastructure and application layers
- **Remediation:** Document annual review process for audit event categories

### AU.L2-3.3.4 — Alert on audit process failure
- **Status:** Partially Implemented
- **Evidence:** CloudWatch alarms for EC2 status checks (`modules/monitoring/cloudwatch.tf`)
- **Remediation:** Add CloudWatch alarm for CloudTrail log delivery failures

### AU.L2-3.3.5 — Correlate audit review and reporting
- **Status:** Gap
- **Evidence:** Logs stored in separate S3 buckets
- **Remediation:** Implement centralized log analysis (e.g., CloudWatch Logs Insights, or third-party SIEM)

### AU.L2-3.3.6 — Provide audit reduction and report generation
- **Status:** Gap
- **Evidence:** Raw logs in S3
- **Remediation:** Implement log analysis tooling with query and reporting capabilities

### AU.L2-3.3.7 — Provide system clocks synchronized to authoritative source
- **Status:** Implemented
- **Evidence:** EC2 instances use Amazon Time Sync Service (NTP) by default, all AWS services use synchronized timestamps
- **Remediation:** None

### AU.L2-3.3.8 — Protect audit information
- **Status:** Implemented
- **Evidence:** S3 buckets encrypted with KMS, public access blocked on all log buckets, bucket policies restrict write to service principals only, versioning on state bucket
- **Remediation:** None

### AU.L2-3.3.9 — Limit management of audit functionality
- **Status:** Partially Implemented
- **Evidence:** IAM policies restrict CloudTrail/S3 management, Terraform-managed infrastructure limits ad-hoc changes
- **Remediation:** Add IAM policy denying CloudTrail stop/delete for non-admin users

---

## Configuration Management (CM) — 9 Practices

### CM.L2-3.4.1 — Establish and maintain baseline configurations
- **Status:** Implemented
- **Evidence:** All infrastructure defined as Terraform (`terraform/` directory), GitLab configured via `gitlab.rb` in `user_data.sh`, AMI baseline is Amazon Linux 2023
- **Remediation:** None

### CM.L2-3.4.2 — Establish and enforce security configuration settings
- **Status:** Implemented
- **Evidence:** Checkov security scanning (`.checkov.yml`), IMDSv2 enforced, TLS 1.3 policy, KMS encryption on all storage, security group least-privilege
- **Remediation:** None

### CM.L2-3.4.3 — Track, review, and control changes
- **Status:** Implemented
- **Evidence:** GitLab itself provides version control, Terraform state tracks infrastructure changes, CloudTrail logs all API changes
- **Remediation:** None

### CM.L2-3.4.4 — Analyze security impact of changes
- **Status:** Partially Implemented
- **Evidence:** `terraform plan` shows change impact, Checkov scans on Terraform changes
- **Remediation:** Document change management process requiring security review before apply

### CM.L2-3.4.5 — Define and enforce physical and logical access restrictions
- **Status:** Implemented
- **Evidence:** No SSH key pair on EC2 (SSM only), private subnets, security groups, IAM policies, Tailscale ACLs
- **Remediation:** None

### CM.L2-3.4.6 — Employ least functionality
- **Status:** Implemented
- **Evidence:** Minimal security group rules, VPC endpoints only for required services, GitLab signup disabled, Gravatar disabled, outbound webhooks restricted
- **Remediation:** None

### CM.L2-3.4.7 — Restrict, disable, or prevent nonessential programs
- **Status:** Partially Implemented
- **Evidence:** Amazon Linux 2023 minimal install, only required packages in `user_data.sh`
- **Remediation:** Document approved software list for the GitLab instance

### CM.L2-3.4.8 — Apply deny-by-exception policy for unauthorized software
- **Status:** Gap
- **Evidence:** No application whitelisting configured
- **Remediation:** Consider implementing AIDE or similar file integrity monitoring

### CM.L2-3.4.9 — Control and monitor user-installed software
- **Status:** Partially Implemented
- **Evidence:** EC2 access only via SSM (no SSH keys deployed), IAM controls who can start sessions
- **Remediation:** Document policy restricting software installation on GitLab server

---

## Identification and Authentication (IA) — 11 Practices

### IA.L2-3.5.1 — Identify system users and processes
- **Status:** Implemented
- **Evidence:** Google OAuth provides user identification, IAM roles identify AWS processes, GitLab users linked to Google identity
- **Remediation:** None

### IA.L2-3.5.2 — Authenticate users and processes
- **Status:** Implemented
- **Evidence:** Google OAuth (MFA via Google), SSH keys for Git, IAM instance profile for AWS API, Personal Access Tokens for API
- **Remediation:** None

### IA.L2-3.5.3 — Use multifactor authentication for local and network access
- **Status:** Partially Implemented
- **Evidence:** Google OAuth supports MFA (enforced at Google Workspace level), Tailscale supports MFA
- **Remediation:** Ensure Google Workspace MFA is enforced for all users; document MFA policy

### IA.L2-3.5.4 — Employ replay-resistant authentication
- **Status:** Implemented
- **Evidence:** OAuth 2.0 with state parameter, TLS 1.3, SSH protocol replay resistance
- **Remediation:** None

### IA.L2-3.5.5 — Prevent reuse of identifiers
- **Status:** Implemented
- **Evidence:** Google OAuth enforces unique identifiers, GitLab usernames unique per instance
- **Remediation:** None

### IA.L2-3.5.6 — Disable identifiers after inactivity
- **Status:** Gap
- **Evidence:** No automated deprovisioning configured
- **Remediation:** Implement GitLab user deactivation after 90 days of inactivity (Admin > Settings > Account and Limit)

### IA.L2-3.5.7 — Enforce minimum password complexity
- **Status:** Implemented
- **Evidence:** Password authentication delegated to Google OAuth (Google enforces complexity), GitLab local passwords available for root account only
- **Remediation:** None

### IA.L2-3.5.8 — Prohibit password reuse
- **Status:** Implemented
- **Evidence:** Delegated to Google OAuth password policy
- **Remediation:** None

### IA.L2-3.5.9 — Allow temporary passwords for system logons with immediate change
- **Status:** Partially Implemented
- **Evidence:** Initial root password set via Secrets Manager, intended for one-time use
- **Remediation:** Document procedure to change root password after initial setup

### IA.L2-3.5.10 — Store and transmit only cryptographically-protected passwords
- **Status:** Implemented
- **Evidence:** Passwords stored in Secrets Manager (encrypted), transmitted over TLS 1.3, GitLab stores password hashes (bcrypt)
- **Remediation:** None

### IA.L2-3.5.11 — Obscure feedback of authentication information
- **Status:** Implemented
- **Evidence:** GitLab masks password input, OAuth redirects don't expose credentials, Secrets Manager values not logged
- **Remediation:** None

---

## Incident Response (IR) — 3 Practices

### IR.L2-3.6.1 — Establish incident handling capability
- **Status:** Gap (Organizational)
- **Evidence:** CloudTrail and VPC Flow Logs provide forensic data
- **Remediation:** Develop incident response plan and designate incident response team

### IR.L2-3.6.2 — Track, document, and report incidents
- **Status:** Gap (Organizational)
- **Evidence:** Logging infrastructure exists
- **Remediation:** Implement incident tracking system and reporting procedures

### IR.L2-3.6.3 — Test incident response capability
- **Status:** Gap (Organizational)
- **Evidence:** None
- **Remediation:** Schedule annual incident response exercises

---

## Maintenance (MA) — 6 Practices

### MA.L2-3.7.1 — Perform maintenance
- **Status:** Partially Implemented
- **Evidence:** GitLab backup cron (`user_data.sh`), `yum update` available via SSM
- **Remediation:** Document maintenance schedule (patching, GitLab upgrades, backup verification)

### MA.L2-3.7.2 — Control system maintenance tools
- **Status:** Partially Implemented
- **Evidence:** SSM Session Manager provides controlled access, no SSH keys deployed
- **Remediation:** Document approved maintenance tools and procedures

### MA.L2-3.7.3 — Ensure off-site maintenance equipment is sanitized
- **Status:** N/A
- **Evidence:** Cloud-based system, no off-site equipment
- **Remediation:** None

### MA.L2-3.7.4 — Check media containing diagnostic programs for malicious code
- **Status:** N/A
- **Evidence:** Cloud-based, software installed from package repos
- **Remediation:** None

### MA.L2-3.7.5 — Require multifactor authentication for remote maintenance
- **Status:** Partially Implemented
- **Evidence:** SSM requires IAM authentication, Tailscale supports MFA
- **Remediation:** Enforce MFA on AWS accounts used for maintenance

### MA.L2-3.7.6 — Supervise maintenance activities of personnel without authorization
- **Status:** Partially Implemented
- **Evidence:** SSM sessions logged, CloudTrail tracks all actions
- **Remediation:** Document supervision procedures for third-party maintenance

---

## Media Protection (MP) — 9 Practices

### MP.L2-3.8.1 — Protect system media containing CUI
- **Status:** Implemented
- **Evidence:** EBS volumes encrypted (`modules/gitlab/ec2.tf`), S3 buckets encrypted with KMS, all data in private VPC
- **Remediation:** None

### MP.L2-3.8.2 — Limit access to CUI on system media
- **Status:** Implemented
- **Evidence:** IAM policies restrict S3/EBS access, security groups limit network access, Tailscale controls device access
- **Remediation:** None

### MP.L2-3.8.3 — Sanitize or destroy media before disposal
- **Status:** Implemented (AWS responsibility)
- **Evidence:** AWS handles physical media destruction per AWS shared responsibility model, EBS volumes encrypted so data is cryptographically erased on deletion
- **Remediation:** None

### MP.L2-3.8.4 — Mark media with CUI indicators
- **Status:** Gap
- **Evidence:** None
- **Remediation:** Add CUI marking tags to S3 buckets and EBS volumes via Terraform tags

### MP.L2-3.8.5 — Control access to media with CUI during transport
- **Status:** Implemented
- **Evidence:** All data in transit encrypted (TLS 1.3, WireGuard, SSH), no physical media transport
- **Remediation:** None

### MP.L2-3.8.6 — Implement cryptographic mechanisms during transport
- **Status:** Implemented
- **Evidence:** TLS 1.3 (`ELBSecurityPolicy-TLS13-1-2-2021-06`), WireGuard (Tailscale), S3 encryption in transit enforced
- **Remediation:** None

### MP.L2-3.8.7 — Control use of removable media
- **Status:** N/A
- **Evidence:** Cloud-based EC2 instance, no removable media interfaces
- **Remediation:** None

### MP.L2-3.8.8 — Prohibit use of portable storage without owner
- **Status:** N/A
- **Evidence:** Cloud-based system
- **Remediation:** None

### MP.L2-3.8.9 — Protect backup CUI at storage locations
- **Status:** Implemented
- **Evidence:** Backups in S3 with KMS encryption, versioning, public access blocked (`modules/gitlab/backup.tf`), Glacier lifecycle for long-term retention
- **Remediation:** None

---

## Personnel Security (PS) — 2 Practices

### PS.L2-3.9.1 — Screen individuals prior to authorizing access
- **Status:** Gap (Organizational)
- **Evidence:** None (organizational process)
- **Remediation:** Implement background screening for personnel accessing CUI systems

### PS.L2-3.9.2 — Protect CUI during personnel actions
- **Status:** Partially Implemented
- **Evidence:** Google OAuth can be disabled centrally (deprovisioning via Google Workspace), Tailscale device removal
- **Remediation:** Document offboarding procedure including GitLab access revocation

---

## Physical Protection (PE) — 6 Practices

### PE.L2-3.10.1 — Limit physical access
- **Status:** N/A (AWS responsibility)
- **Evidence:** AWS data centers, SOC 2 / ISO 27001 certified
- **Remediation:** None

### PE.L2-3.10.2 — Protect and monitor physical facility
- **Status:** N/A (AWS responsibility)
- **Remediation:** None

### PE.L2-3.10.3 — Escort visitors
- **Status:** N/A (AWS responsibility)
- **Remediation:** None

### PE.L2-3.10.4 — Maintain audit logs of physical access
- **Status:** N/A (AWS responsibility)
- **Remediation:** None

### PE.L2-3.10.5 — Control and manage physical access devices
- **Status:** N/A (AWS responsibility)
- **Remediation:** None

### PE.L2-3.10.6 — Enforce safeguarding measures for CUI at alternate work sites
- **Status:** Partially Implemented
- **Evidence:** Tailscale encrypted tunnel, TLS 1.3 for all web access
- **Remediation:** Document acceptable use policy for accessing CUI from remote/alternate locations

---

## Risk Assessment (RA) — 3 Practices

### RA.L2-3.11.1 — Periodically assess risk
- **Status:** Partially Implemented
- **Evidence:** Checkov scans for infrastructure security (`.checkov.yml`), this gap analysis document
- **Remediation:** Schedule annual risk assessment reviews

### RA.L2-3.11.2 — Scan for vulnerabilities periodically and on change
- **Status:** Partially Implemented
- **Evidence:** Checkov scans Terraform on change, Amazon Inspector available for EC2
- **Remediation:** Enable Amazon Inspector for EC2 vulnerability scanning; schedule periodic GitLab security updates

### RA.L2-3.11.3 — Remediate vulnerabilities per risk assessment
- **Status:** Gap
- **Evidence:** No formal remediation tracking
- **Remediation:** Document vulnerability remediation SLAs and tracking process

---

## Security Assessment (CA) — 4 Practices

### CA.L2-3.12.1 — Periodically assess security controls
- **Status:** Partially Implemented
- **Evidence:** This gap analysis, Checkov automated scanning
- **Remediation:** Schedule annual security control assessments

### CA.L2-3.12.2 — Develop and implement plans of action
- **Status:** Partially Implemented
- **Evidence:** This document identifies gaps with remediation steps
- **Remediation:** Create formal POA&M tracking document

### CA.L2-3.12.3 — Monitor security controls on an ongoing basis
- **Status:** Partially Implemented
- **Evidence:** CloudWatch alarms (`modules/monitoring/cloudwatch.tf`), CloudTrail, VPC Flow Logs
- **Remediation:** Implement continuous monitoring dashboard

### CA.L2-3.12.4 — Develop and update system security plans
- **Status:** Partially Implemented
- **Evidence:** Design document (`docs/plans/2026-03-02-airgapped-gitlab-design.md`), this gap analysis
- **Remediation:** Develop formal System Security Plan (SSP) document

---

## System and Communications Protection (SC) — 16 Practices

### SC.L2-3.13.1 — Monitor and control communications at boundaries
- **Status:** Implemented
- **Evidence:** VPC with security groups, NAT Gateway for controlled outbound, VPC Flow Logs, ALB access logs, no public endpoints
- **Remediation:** None

### SC.L2-3.13.2 — Employ architectural designs to promote security
- **Status:** Implemented
- **Evidence:** Defense-in-depth: VPN (Tailscale) > ALB (TLS) > private subnet > security groups > EC2, separate data volume, encrypted storage
- **Remediation:** None

### SC.L2-3.13.3 — Separate user functionality from system management
- **Status:** Implemented
- **Evidence:** GitLab web UI for users, SSM for system management, separate IAM roles
- **Remediation:** None

### SC.L2-3.13.4 — Prevent unauthorized and unintended information transfer
- **Status:** Partially Implemented
- **Evidence:** Security groups restrict traffic, outbound webhooks disabled in GitLab, Gravatar disabled
- **Remediation:** Consider implementing DLP controls for Git push content

### SC.L2-3.13.5 — Implement subnetworks for publicly accessible components
- **Status:** Implemented
- **Evidence:** Public subnets for NAT Gateway only, GitLab in private subnet, ALB internal, no public-facing components
- **Remediation:** None

### SC.L2-3.13.6 — Deny network traffic by default
- **Status:** Implemented
- **Evidence:** Security groups deny by default (AWS behavior), explicit allow rules only for required ports
- **Remediation:** None

### SC.L2-3.13.7 — Prevent remote devices from establishing split tunneling
- **Status:** Partially Implemented
- **Evidence:** Tailscale can enforce exit node policies
- **Remediation:** Configure Tailscale ACLs to prevent split tunneling for CUI-accessing devices

### SC.L2-3.13.8 — Implement cryptographic mechanisms to prevent unauthorized disclosure during transmission
- **Status:** Implemented
- **Evidence:** TLS 1.3 on ALB, WireGuard via Tailscale, SSH for Git, KMS for S3/EBS
- **Remediation:** None

### SC.L2-3.13.9 — Terminate network connections after inactivity
- **Status:** Implemented
- **Evidence:** GitLab session timeout (480 min), ALB idle timeout (default 60s), SSH timeout configurable
- **Remediation:** None

### SC.L2-3.13.10 — Establish and manage cryptographic keys
- **Status:** Partially Implemented
- **Evidence:** AWS KMS manages encryption keys, ACM manages TLS certificates, SSH keys managed per-user
- **Remediation:** Document key management procedures including rotation schedules

### SC.L2-3.13.11 — Employ FIPS-validated cryptography
- **Status:** Partially Implemented
- **Evidence:** `fips-mode-setup --enable` in `user_data.sh`, AWS KMS uses FIPS 140-2 validated HSMs, ALB uses FIPS-compliant TLS
- **Remediation:** Verify FIPS mode is active post-boot; consider FIPS-validated AMI

### SC.L2-3.13.12 — Prohibit remote activation of collaborative computing devices
- **Status:** N/A
- **Evidence:** No collaborative computing devices (cameras, microphones) on EC2
- **Remediation:** None

### SC.L2-3.13.13 — Control and monitor use of mobile code
- **Status:** Partially Implemented
- **Evidence:** GitLab CI/CD runners not deployed (no mobile code execution on server)
- **Remediation:** Document policy for CI/CD runner deployment if added later

### SC.L2-3.13.14 — Control and monitor use of VoIP
- **Status:** N/A
- **Evidence:** No VoIP services
- **Remediation:** None

### SC.L2-3.13.15 — Protect authenticity of communications sessions
- **Status:** Implemented
- **Evidence:** TLS 1.3 with ACM certificates, OAuth state parameter, CSRF protection in GitLab
- **Remediation:** None

### SC.L2-3.13.16 — Protect CUI at rest
- **Status:** Implemented
- **Evidence:** EBS volumes encrypted (`modules/gitlab/ec2.tf` — `encrypted = true`), S3 buckets encrypted with KMS, Secrets Manager encrypted
- **Remediation:** None

---

## System and Information Integrity (SI) — 7 Practices

### SI.L2-3.14.1 — Identify and correct system flaws in a timely manner
- **Status:** Partially Implemented
- **Evidence:** Amazon Linux 2023 receives security updates, GitLab releases regular patches, `dnf update` available via SSM
- **Remediation:** Document patching schedule and SLAs (e.g., critical within 48 hours)

### SI.L2-3.14.2 — Provide protection from malicious code
- **Status:** Partially Implemented
- **Evidence:** Amazon Linux 2023 includes basic security, SELinux available
- **Remediation:** Enable SELinux enforcing mode; consider ClamAV for file scanning on Git pushes

### SI.L2-3.14.3 — Monitor security alerts and advisories
- **Status:** Gap
- **Evidence:** None configured
- **Remediation:** Subscribe to GitLab security mailing list, AWS Security Bulletins, and Amazon Linux security advisories

### SI.L2-3.14.4 — Update malicious code protection mechanisms
- **Status:** Partially Implemented
- **Evidence:** `dnf update` provides security updates
- **Remediation:** Configure automated security updates (`dnf-automatic`)

### SI.L2-3.14.5 — Perform periodic scans and real-time monitoring
- **Status:** Partially Implemented
- **Evidence:** CloudWatch monitoring for CPU/status, VPC Flow Logs for network monitoring
- **Remediation:** Enable Amazon Inspector for vulnerability scanning; add disk space monitoring alarms

### SI.L2-3.14.6 — Monitor inbound and outbound communications for attacks
- **Status:** Partially Implemented
- **Evidence:** VPC Flow Logs, ALB access logs, security groups filter traffic
- **Remediation:** Consider AWS GuardDuty for threat detection

### SI.L2-3.14.7 — Identify unauthorized use of the system
- **Status:** Partially Implemented
- **Evidence:** CloudTrail logs, GitLab audit logs, VPC Flow Logs
- **Remediation:** Implement alerting on anomalous access patterns (e.g., off-hours logins, unusual API calls)
