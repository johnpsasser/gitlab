# Incident Response Plan

**System**: GitLab CE (Self-Hosted) on AWS EC2
**Classification**: DoD Impact Level 2 (IL2)
**Framework**: NIST SP 800-61 Rev 2, Computer Security Incident Handling Guide
**Version**: 1.0
**Effective Date**: 2026-03-03
**Last Reviewed**: 2026-03-03
**Document Owner**: [System Owner Name]
**Data Classification**: CUI // SP-NOFORN when populated with operational data

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [Roles and Responsibilities](#2-roles-and-responsibilities)
3. [Incident Classification](#3-incident-classification)
4. [Detection and Analysis](#4-detection-and-analysis)
5. [Containment Strategies](#5-containment-strategies)
6. [Eradication and Recovery](#6-eradication-and-recovery)
7. [Post-Incident Activity](#7-post-incident-activity)
8. [Contact List](#8-contact-list)
9. [Incident Reporting Procedures](#9-incident-reporting-procedures)
10. [Appendix A: GuardDuty Finding Response Runbook](#appendix-a-guardduty-finding-response-runbook)
11. [Appendix B: Unauthorized API Call Response Runbook](#appendix-b-unauthorized-api-call-response-runbook)

---

## 1. Purpose and Scope

### 1.1 Purpose

This Incident Response Plan (IRP) establishes procedures for detecting, analyzing, containing, eradicating, and recovering from cybersecurity incidents affecting the self-hosted GitLab CE deployment on AWS. The plan satisfies NIST 800-53 controls IR-1 (Incident Response Policy and Procedures), IR-4 (Incident Handling), IR-6 (Incident Reporting), and IR-8 (Incident Response Plan) as required for DoD IL2 compliance.

### 1.2 Scope

This plan covers all components of the GitLab CE infrastructure:

- **Compute**: EC2 instance running GitLab CE on Amazon Linux 2023 (private subnet)
- **Network**: VPC, public/private subnets across 2 AZs, ALB, NAT Gateway, VPC endpoints
- **Security**: AWS WAF (OWASP rules, rate limiting), security groups, IAM roles/policies
- **Data**: EBS volumes (root + data), S3 backup bucket, Secrets Manager secrets
- **Monitoring**: GuardDuty (with malware protection), Security Hub (NIST 800-53 v5), AWS Config, CloudTrail (multi-region), CloudWatch alarms, VPC Flow Logs, Amazon Inspector, ClamAV
- **Encryption**: Customer Managed KMS Keys (general, CloudTrail, EBS)
- **Access**: SSM Session Manager (no SSH), GitLab native auth with mandatory 2FA

### 1.3 Authority

This plan is maintained under the authority of the System Owner and Information System Security Officer (ISSO). It is reviewed and updated at least annually or after any significant incident.

### 1.4 References

- NIST SP 800-61 Rev 2, Computer Security Incident Handling Guide
- NIST SP 800-53 Rev 5, Security and Privacy Controls
- DoD Cloud Computing Security Requirements Guide (CC SRG)
- CISA Federal Incident Notification Guidelines
- DoD Instruction 8530.01, Cybersecurity Activities Support to DoD Information Network Operations
- This project's DoD IL2 Compliance Mapping (`docs/dod-il2-compliance.md`)

---

## 2. Roles and Responsibilities

### 2.1 Incident Response Team (IRT)

| Role | Responsibilities |
|---|---|
| **Incident Commander (IC)** | Owns the incident lifecycle. Declares severity, authorizes containment actions, coordinates communications, and determines when the incident is resolved. Final authority on all response decisions. |
| **Technical Lead (TL)** | Leads technical investigation and remediation. Analyzes logs (CloudTrail, VPC Flow Logs, GuardDuty findings), executes containment actions (security group changes, WAF rules), and manages system recovery via Terraform and S3 backups. |
| **Communications Lead (CL)** | Manages internal and external notifications. Coordinates with stakeholders, DoD reporting channels, and end users. Maintains the incident timeline and drafts post-incident reports. |

### 2.2 Escalation Authority

| Decision | Authority |
|---|---|
| Declare Severity 1 or 2 incident | Incident Commander |
| Isolate or terminate EC2 instance | Technical Lead (with IC approval) |
| Modify WAF rules or security groups | Technical Lead |
| Notify external parties (DoD, CISA) | Communications Lead (with IC approval) |
| Authorize system rebuild from Terraform | Incident Commander |
| Approve post-incident report for distribution | Incident Commander |

### 2.3 On-Call Rotation

The IRT maintains a 24/7 on-call rotation. The on-call engineer receives SNS alerts from the `aws_sns_topic.alerts` topic and is responsible for initial triage within the response times defined in Section 3.

---

## 3. Incident Classification

### 3.1 Severity Levels

| Severity | Definition | Response Time | Examples |
|---|---|---|---|
| **SEV-1: Critical** | Active compromise, data exfiltration, or complete service loss. Immediate threat to data confidentiality, integrity, or availability. | **15 minutes** initial response; continuous work until contained | Active unauthorized access to GitLab data; GuardDuty `Trojan` or `CryptoCurrency` finding on EC2; KMS key compromise; ransomware detection by ClamAV; complete GitLab service outage |
| **SEV-2: High** | Attempted or partial compromise, significant vulnerability exploitation, or major service degradation. | **1 hour** initial response | Successful brute-force authentication; unauthorized IAM API calls detected by CloudTrail; Inspector critical CVE with known exploit; WAF bypass detected; EBS volume or S3 bucket policy modification |
| **SEV-3: Moderate** | Suspicious activity, policy violations, or minor service impact requiring investigation. | **4 hours** initial response | Elevated GuardDuty `Recon` findings; repeated WAF-blocked attacks from single source; unauthorized security group modification detected by Config; failed SSM session attempts; GitLab admin account anomalies |
| **SEV-4: Low** | Informational security events, minor policy deviations, or routine findings. | **24 hours** initial response | Security Hub low-severity findings; Inspector medium/low CVEs; single failed login attempts; routine ClamAV scan clean results; AWS Config minor drift |

### 3.2 Severity Adjustment Criteria

Severity may be escalated if:

- The scope of impact expands (e.g., additional systems or data affected)
- Indicators of a coordinated or advanced persistent threat emerge
- Data classified at IL2 or above is confirmed exposed
- The incident attracts external attention or media coverage
- Recovery time exceeds initial estimates

---

## 4. Detection and Analysis

### 4.1 Detection Sources

| Source | What It Detects | Location | Alert Mechanism |
|---|---|---|---|
| **GuardDuty** | Threat intelligence matches, anomalous API calls, network anomalies, malware on EC2/EBS, DNS-based exfiltration | `modules/security/guardduty.tf` | Security Hub aggregation; EventBridge rules to SNS |
| **Security Hub** | NIST 800-53 v5 control failures, AWS Foundational Best Practices violations, aggregated findings from GuardDuty/Inspector/Config | `modules/security/securityhub.tf` | Security Hub dashboard; EventBridge to SNS |
| **CloudWatch Alarms** | CPU utilization >90%, EC2 status check failures, unauthorized API calls (via CloudTrail metric filters) | `modules/monitoring/cloudwatch.tf` | SNS topic `aws_sns_topic.alerts` |
| **CloudTrail** | All AWS API calls across all regions, console sign-in events, IAM changes | `modules/monitoring/cloudtrail.tf` | CloudWatch Logs metric filters; S3 log analysis |
| **VPC Flow Logs** | Network connection attempts, rejected flows, unusual traffic patterns, data volume anomalies | `modules/networking/flow_logs.tf` | CloudWatch Logs analysis |
| **WAF Logs** | Blocked requests (OWASP rule matches, known bad inputs), rate-limited IPs, request patterns | `modules/waf/waf.tf` | CloudWatch Logs; WAF metrics |
| **Amazon Inspector** | CVE findings on EC2, OS and application vulnerability assessments | Inspector console / EventBridge | Security Hub integration; EventBridge to SNS |
| **ClamAV** | Malware, trojans, viruses detected on file system | EC2 instance (installed via `user_data.sh`) | Local logs; CloudWatch Logs agent |
| **AWS Config** | Configuration changes, compliance rule violations, resource drift from baseline | `modules/security/config.tf` | Security Hub integration; SNS notifications |
| **ALB Access Logs** | HTTP request patterns, error rates, suspicious URIs | `modules/alb/logging.tf` | S3 log analysis; CloudWatch Logs Insights |

### 4.2 Initial Analysis Checklist

When an alert is received, the on-call engineer performs the following:

1. **Acknowledge the alert** -- Record the timestamp, source, and alert details in the incident log.
2. **Validate the finding** -- Confirm the alert is not a false positive:
   - Check GuardDuty finding details (severity, type, resource affected)
   - Cross-reference with CloudTrail for correlated API activity
   - Review VPC Flow Logs for associated network connections
   - Check Security Hub for related findings
3. **Determine scope** -- Identify all affected resources:
   - EC2 instance (is the GitLab instance compromised?)
   - IAM entities (are credentials compromised?)
   - S3 buckets (have backup or log buckets been accessed?)
   - KMS keys (have encryption keys been used abnormally?)
4. **Assign severity** -- Use the classification table in Section 3.
5. **Notify the Incident Commander** -- If severity is SEV-1 or SEV-2, page the IC immediately.
6. **Begin evidence preservation** -- Before taking containment actions:
   - Capture EC2 instance metadata via SSM: `aws ssm start-session`
   - Create EBS snapshots of all attached volumes
   - Export relevant CloudTrail events to a dedicated S3 prefix
   - Screenshot GuardDuty/Security Hub findings
   - Record current security group rules and WAF configuration

### 4.3 Evidence Preservation

All evidence must be preserved with chain-of-custody documentation:

- **EBS Snapshots**: Create snapshots of root and data volumes before any containment action. Tag snapshots with `Incident-ID` and `Timestamp`.
- **CloudTrail Logs**: CloudTrail logs are immutable in S3 with log file validation enabled. Identify the relevant time window and export to a separate forensics prefix.
- **VPC Flow Logs**: Retain in CloudWatch Logs (365-day retention configured). Export relevant time ranges to S3.
- **Memory Capture**: If warranted (SEV-1), use SSM Run Command to capture process listings, network connections, and memory dumps before isolation.
- **WAF Logs**: Export relevant WAF log entries from CloudWatch Logs for the incident time window.

---

## 5. Containment Strategies

### 5.1 Immediate Containment (Short-Term)

#### 5.1.1 Network Isolation via Security Group

Isolate the EC2 instance by replacing its security group with a forensics-only group that blocks all inbound/outbound traffic except SSM:

```bash
# Create forensics security group (if not pre-staged)
aws ec2 create-security-group \
  --group-name "incident-forensics-sg" \
  --description "Forensics isolation - incident response" \
  --vpc-id <vpc-id>

# Allow only SSM endpoints (required for investigation access)
aws ec2 authorize-security-group-egress \
  --group-id <forensics-sg-id> \
  --protocol tcp --port 443 \
  --cidr 0.0.0.0/0  # SSM uses HTTPS to VPC endpoints

# Swap the instance security groups
aws ec2 modify-instance-attribute \
  --instance-id <instance-id> \
  --groups <forensics-sg-id>
```

**Important**: The EC2 instance resides in a private subnet with no public IP. SSM Session Manager access is maintained through VPC endpoints (`modules/networking/endpoints.tf`) and does not require inbound security group rules.

#### 5.1.2 Block Malicious IPs via WAF

Add offending IP addresses to a WAF IP set block rule:

```bash
# Create or update WAF IP set
aws wafv2 create-ip-set \
  --name "incident-block-list" \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses <malicious-ip>/32

# Update WAF WebACL to include block rule referencing the IP set
```

The existing WAF configuration (`modules/waf/waf.tf`) includes rate limiting at 2000 requests per 5 minutes. For active attacks, temporarily reduce this threshold.

#### 5.1.3 Disable Compromised Accounts

**GitLab accounts** -- Block the user via GitLab API or SSM session:

```bash
# Via SSM session on the EC2 instance
sudo gitlab-rails runner "User.find_by(username: '<username>').block!"
```

**IAM credentials** -- If AWS credentials are compromised:

```bash
# Deactivate access keys
aws iam update-access-key --user-name <user> --access-key-id <key-id> --status Inactive

# Revoke all active sessions for an IAM role
aws iam put-role-policy --role-name <role> --policy-name DenyAll --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]}'
```

#### 5.1.4 Revoke GitLab Personal Access Tokens

If PATs are suspected compromised:

```bash
# Via SSM session -- revoke all PATs for a user
sudo gitlab-rails runner "PersonalAccessToken.where(user: User.find_by(username: '<username>')).each(&:revoke!)"
```

### 5.2 Extended Containment

If the initial containment does not resolve the threat:

1. **Detach ALB target group** -- Remove the EC2 instance from the ALB target group to stop all user traffic while preserving the instance for forensics.
2. **Rotate all secrets** -- Use Secrets Manager to rotate the GitLab root password and any other stored secrets.
3. **Rotate KMS keys** -- If key compromise is suspected, create new CMKs and re-encrypt all data.
4. **Disable VPC endpoints** -- If data exfiltration via AWS APIs is suspected, restrict VPC endpoint policies.
5. **Enable enhanced monitoring** -- Increase VPC Flow Log aggregation interval, enable additional CloudWatch metrics.

---

## 6. Eradication and Recovery

### 6.1 Eradication

#### 6.1.1 Determine Root Cause

Before rebuilding, establish the root cause using:

- **CloudTrail**: Identify the initial unauthorized action and method of entry
- **GuardDuty findings**: Determine threat type and attack vector
- **VPC Flow Logs**: Trace network-level activity
- **Inspector findings**: Identify exploited vulnerabilities
- **ClamAV logs**: Identify malware artifacts
- **GitLab audit logs**: Review application-level activity (`/var/log/gitlab/`)

#### 6.1.2 Remove Threat Artifacts

- Terminate the compromised EC2 instance (after forensic snapshots are captured)
- Delete any unauthorized IAM users, roles, or policies
- Remove any unauthorized S3 bucket policies or object ACLs
- Revoke all GitLab personal access tokens system-wide if scope is uncertain
- Clean or quarantine any ClamAV-identified malware

### 6.2 Recovery

#### 6.2.1 Rebuild from Terraform

The entire infrastructure is defined as code. Rebuild with a clean state:

```bash
cd terraform/

# Taint the compromised EC2 instance to force replacement
terraform taint module.gitlab.aws_instance.gitlab

# Plan and review the rebuild
terraform plan -out=recovery.tfplan

# Apply the recovery plan
terraform apply recovery.tfplan
```

The `user_data.sh` bootstrap script will:

1. Install and configure GitLab CE from official repositories
2. Apply hardened `gitlab.rb` configuration (2FA, password policy, session timeouts)
3. Install and configure ClamAV
4. Configure CloudWatch Logs agent
5. Set up daily backup cron jobs

#### 6.2.2 Restore GitLab Data from S3 Backup

```bash
# Via SSM session on the new EC2 instance

# List available backups
aws s3 ls s3://<backup-bucket>/gitlab-backups/ --recursive

# Download the most recent clean backup (pre-incident)
aws s3 cp s3://<backup-bucket>/gitlab-backups/<timestamp>_gitlab_backup.tar /var/opt/gitlab/backups/

# Restore GitLab data
sudo gitlab-backup restore BACKUP=<timestamp>

# Restore configuration
aws s3 cp s3://<backup-bucket>/gitlab-config-backups/latest/ /etc/gitlab/ --recursive
sudo gitlab-ctl reconfigure
```

#### 6.2.3 Secret Rotation

Rotate all secrets after a confirmed compromise:

| Secret | Rotation Method |
|---|---|
| GitLab root password | Secrets Manager rotation; update via `gitlab-rails console` |
| `gitlab-secrets.json` | Restore from pre-incident Secrets Manager backup, then rotate Rails secret key base |
| KMS keys | Create new CMKs via Terraform; re-encrypt all data stores |
| ACM certificate | Request new certificate if private key compromise is suspected |
| IAM instance profile | Terraform will create new role/profile on instance replacement |
| GitLab PATs | Revoke all tokens; users generate new tokens after recovery |

#### 6.2.4 Verification

Before returning the system to service:

1. **Run `terraform plan`** -- Confirm no drift from the defined infrastructure state
2. **Verify Security Hub compliance** -- Check NIST 800-53 v5 findings dashboard
3. **Run Inspector scan** -- Confirm no outstanding critical CVEs
4. **Validate ClamAV** -- Run a full system scan on the new instance
5. **Test GitLab functionality** -- Verify web UI, Git push/pull, 2FA enforcement, and backup jobs
6. **Confirm monitoring** -- Verify CloudWatch alarms, GuardDuty, and SNS notifications are active
7. **Review security groups** -- Confirm the production security groups are correctly applied (not forensics SG)
8. **Test WAF** -- Send test requests to validate WAF rules are functioning

---

## 7. Post-Incident Activity

### 7.1 Lessons Learned

Conduct a post-incident review within **5 business days** of incident closure. Document:

- **Timeline**: Minute-by-minute reconstruction from detection to resolution
- **Root cause**: Technical root cause and contributing factors
- **Detection effectiveness**: How was the incident detected? What was the detection latency?
- **Response effectiveness**: Were containment and eradication procedures adequate?
- **What worked well**: Identify effective processes, tools, and team actions
- **What needs improvement**: Identify gaps in detection, response, or communication
- **Action items**: Specific, assigned, time-bound remediation tasks

### 7.2 Compliance Documentation Updates

After every SEV-1 or SEV-2 incident, update the following:

| Document | Update Required |
|---|---|
| This Incident Response Plan | Incorporate lessons learned; update runbooks |
| DoD IL2 Compliance Mapping (`docs/dod-il2-compliance.md`) | Update control implementation status if gaps were identified |
| System Security Plan (SSP) | Document new risks, controls, or compensating measures |
| Risk Assessment | Re-evaluate risk ratings based on incident |
| Terraform configuration | Implement any infrastructure hardening identified during response |
| Checkov policies | Add custom policies for newly identified misconfigurations |

### 7.3 Timeline Documentation

Maintain a structured incident timeline using the following format:

| Timestamp (UTC) | Action | Actor | Details |
|---|---|---|---|
| YYYY-MM-DD HH:MM | Detection | [Source] | Initial alert description |
| YYYY-MM-DD HH:MM | Triage | [On-call engineer] | Severity assigned, IC notified |
| YYYY-MM-DD HH:MM | Containment | [Technical Lead] | Actions taken |
| YYYY-MM-DD HH:MM | Eradication | [Technical Lead] | Root cause removed |
| YYYY-MM-DD HH:MM | Recovery | [Technical Lead] | System restored and verified |
| YYYY-MM-DD HH:MM | Closure | [Incident Commander] | Incident declared resolved |

### 7.4 Metrics

Track the following metrics across all incidents to measure and improve response capability:

- **Mean Time to Detect (MTTD)**: Time from incident occurrence to detection
- **Mean Time to Respond (MTTR)**: Time from detection to initial response action
- **Mean Time to Contain (MTTC)**: Time from detection to successful containment
- **Mean Time to Recover (MTTRec)**: Time from containment to full service restoration
- **False positive rate**: Percentage of alerts that were false positives
- **Incidents by severity**: Monthly breakdown by SEV-1 through SEV-4

---

## 8. Contact List

> **Note**: Replace all placeholder values with actual contact information. This section becomes CUI when populated.

### 8.1 Incident Response Team

| Role | Name | Email | Phone | Alternate |
|---|---|---|---|---|
| Incident Commander (Primary) | [Name] | [Email] | [Phone] | [Alternate Name] |
| Incident Commander (Backup) | [Name] | [Email] | [Phone] | -- |
| Technical Lead (Primary) | [Name] | [Email] | [Phone] | [Alternate Name] |
| Technical Lead (Backup) | [Name] | [Email] | [Phone] | -- |
| Communications Lead | [Name] | [Email] | [Phone] | [Alternate Name] |
| System Owner | [Name] | [Email] | [Phone] | -- |
| ISSO | [Name] | [Email] | [Phone] | -- |

### 8.2 External Contacts

| Organization | Purpose | Contact Method | Notes |
|---|---|---|---|
| AWS Support | Infrastructure issues, GuardDuty escalation | AWS Support Console / [Phone] | Requires Business or Enterprise support plan |
| CISA (US-CERT) | Federal incident reporting | https://www.cisa.gov/report / (888) 282-0870 | Required for federal systems within 72 hours |
| DoD Cyber Crime Center (DC3) | DoD cyber incident reporting | https://www.dc3.mil | Required per DoDI 8530.01 |
| DISA JFHQ-DODIN | DoD network defense coordination | [Contact method per org policy] | Category reporting per CJCSM 6510.01B |
| DNS Provider (Cloudflare) | DNS record changes during incident | Cloudflare dashboard / [Account email] | DNS is external to this deployment |

---

## 9. Incident Reporting Procedures

### 9.1 NIST 800-53 IR-6 Compliance

This section satisfies NIST 800-53 IR-6 (Incident Reporting) requirements. All security incidents must be reported to the appropriate authorities within the timelines specified below.

### 9.2 Internal Reporting

| Severity | Notify | Timeline | Method |
|---|---|---|---|
| SEV-1 | Incident Commander, System Owner, ISSO, all IRT members | **Immediately** (within 15 minutes of detection) | Phone call + SNS alert + email |
| SEV-2 | Incident Commander, System Owner, ISSO | **Within 1 hour** of detection | Phone call + email |
| SEV-3 | Incident Commander, Technical Lead | **Within 4 hours** of detection | Email |
| SEV-4 | Technical Lead | **Within 24 hours** (next business day) | Email or ticketing system |

### 9.3 DoD Reporting Requirements

Per DoD Instruction 8530.01 and CJCSM 6510.01B, cyber incidents must be reported to the DoD as follows:

| Category | Description | Reporting Timeline | Report To |
|---|---|---|---|
| CAT 1 | Root-level compromise, data exfiltration confirmed | **Within 1 hour** of discovery | DC3, JFHQ-DODIN, CISA |
| CAT 2 | Unauthorized user-level access | **Within 1 hour** of discovery | DC3, JFHQ-DODIN |
| CAT 3 | Unsuccessful activity attempt (detected and contained) | **Within 24 hours** | DC3 |
| CAT 4 | Denial of service | **Within 1 hour** if ongoing | DC3, JFHQ-DODIN |
| CAT 5 | Non-compliance, policy violation | **Within 24 hours** | ISSO, System Owner |
| CAT 6 | Reconnaissance, probing | **Within 72 hours** | DC3 |
| CAT 7 | Malicious logic (malware) | **Within 1 hour** of discovery | DC3, JFHQ-DODIN |

### 9.4 CISA Reporting (Federal)

Per CISA Federal Incident Notification Guidelines:

- **All confirmed incidents** must be reported to CISA within **72 hours** of determination
- **Ransomware attacks** must be reported within **24 hours**
- Reports submitted via https://www.cisa.gov/report or by calling (888) 282-0870
- Include: incident type, date/time of detection, systems affected, indicators of compromise (IOCs), impact assessment

### 9.5 Incident Report Format

All formal incident reports must include:

1. **Incident identifier** (unique tracking number)
2. **Date and time of detection** (UTC)
3. **Date and time of incident occurrence** (UTC, if known)
4. **Incident category** (per DoD categorization above)
5. **Severity level** (SEV-1 through SEV-4)
6. **Systems affected** (EC2 instance ID, IP addresses, GitLab version)
7. **Description of incident** (technical narrative)
8. **Impact assessment** (data compromised, service disruption duration)
9. **Indicators of compromise** (IP addresses, file hashes, API calls)
10. **Containment actions taken**
11. **Eradication and recovery actions**
12. **Current status** (ongoing, contained, resolved)
13. **Point of contact** (name, email, phone)

### 9.6 Record Retention

All incident records, reports, evidence, and communications must be retained for a minimum of **3 years** per NIST 800-53 AU-11 and DoD records management requirements.

---

## Appendix A: GuardDuty Finding Response Runbook

### A.1 Overview

Amazon GuardDuty continuously monitors the AWS account for malicious activity. This runbook provides step-by-step response procedures for common GuardDuty finding types. GuardDuty is configured in `modules/security/guardduty.tf` with S3 and malware protection enabled.

### A.2 Finding Severity Mapping

| GuardDuty Severity | IRP Severity | Action |
|---|---|---|
| High (7.0-8.9) | SEV-1 | Immediate response; page IC |
| Medium (4.0-6.9) | SEV-2 or SEV-3 | Investigate within 1-4 hours |
| Low (1.0-3.9) | SEV-4 | Review within 24 hours |

### A.3 Response by Finding Type

#### Backdoor Findings (e.g., `Backdoor:EC2/C&CActivity.B`)

**Severity**: SEV-1

1. **Immediately isolate** the EC2 instance (Section 5.1.1 -- swap to forensics SG)
2. Create EBS snapshots for forensic analysis
3. Capture running processes via SSM: `ps auxf`, `ss -tlnp`, `netstat -an`
4. Check ClamAV scan results: `sudo clamscan -r /var/opt/gitlab/`
5. Review VPC Flow Logs for C2 communication destinations
6. Cross-reference destination IPs with GuardDuty threat intelligence
7. Rebuild the EC2 instance from Terraform (Section 6.2.1)
8. Report as DoD CAT 1 within 1 hour

#### CryptoCurrency Findings (e.g., `CryptoCurrency:EC2/BitcoinTool.B`)

**Severity**: SEV-1

1. **Immediately isolate** the EC2 instance
2. Capture process listing and CPU utilization via SSM
3. Identify the mining process: `top -bn1`, `ps aux | grep -i mine`
4. Create EBS snapshots
5. Terminate the compromised instance and rebuild from Terraform
6. Investigate initial access vector via CloudTrail
7. Report as DoD CAT 7 (malicious logic) within 1 hour

#### UnauthorizedAccess Findings (e.g., `UnauthorizedAccess:IAMUser/MaliciousIPCaller`)

**Severity**: SEV-2

1. Identify the IAM entity from the finding details
2. Check CloudTrail for all API calls made by this entity in the last 24 hours
3. If the entity is the GitLab instance role:
   - Review instance metadata access logs (IMDSv2 is required)
   - Check for credential exfiltration attempts
   - Rotate the instance role by replacing the instance via Terraform
4. If the entity is a human IAM user:
   - Deactivate all access keys immediately
   - Revoke active sessions
   - Reset console password
5. Document all affected resources and API calls
6. Report as DoD CAT 2 within 1 hour

#### Recon Findings (e.g., `Recon:EC2/PortProbeUnprotectedPort`)

**Severity**: SEV-3

1. Review the source IP in the finding
2. Check WAF logs for additional activity from this IP
3. Add the IP to the WAF block list if activity is persistent (Section 5.1.2)
4. Review security group rules to confirm no unintended open ports
5. Verify the ALB is the only public-facing component
6. Report as DoD CAT 6 within 72 hours

#### Trojan Findings (e.g., `Trojan:EC2/PhishingDomainRequest!DNS`)

**Severity**: SEV-1

1. **Immediately isolate** the EC2 instance
2. Run ClamAV full scan via SSM: `sudo clamscan -r / --exclude-dir=/proc --exclude-dir=/sys`
3. Check DNS query logs for the phishing domain
4. Create EBS snapshots for forensic analysis
5. Identify the process making the DNS request: `ss -tlnp`, check `/proc/*/fd`
6. Rebuild from Terraform and restore from a known-clean backup
7. Report as DoD CAT 7 within 1 hour

#### Malware Findings (GuardDuty Malware Protection)

**Severity**: SEV-1

1. Review the GuardDuty malware finding for file path and hash
2. **Immediately isolate** the EC2 instance
3. Cross-reference with ClamAV detection logs
4. Create EBS snapshots (GuardDuty may have already created a snapshot for scanning)
5. Identify how the malware was introduced (file upload, package install, lateral movement)
6. Rebuild from Terraform; restore from pre-infection backup
7. Report as DoD CAT 7 within 1 hour

### A.4 False Positive Handling

If a GuardDuty finding is determined to be a false positive after investigation:

1. Document the investigation and reasoning in the incident log
2. Archive the finding in GuardDuty (do not suppress without documentation)
3. If the finding is recurring and confirmed benign, create a suppression filter with documented justification
4. Review suppression filters quarterly to ensure they remain valid

---

## Appendix B: Unauthorized API Call Response Runbook

### B.1 Overview

CloudTrail captures all AWS API calls. A CloudWatch metric filter in `modules/monitoring/cloudwatch.tf` triggers an alarm on unauthorized API calls (those returning `AccessDenied` or `UnauthorizedAccess` error codes). This runbook provides the response procedure.

### B.2 Detection

The CloudWatch alarm `UnauthorizedAPICalls` fires when the metric filter detects API calls with the following error codes in CloudTrail:

- `AccessDenied`
- `UnauthorizedAccess`
- `Client.UnauthorizedAccess`

### B.3 Response Procedure

#### Step 1: Retrieve the CloudTrail Events

```bash
# Query CloudTrail for unauthorized calls in the last hour
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<event-name> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --query 'Events[?contains(CloudTrailEvent, `AccessDenied`)]'
```

Alternatively, use CloudWatch Logs Insights:

```
fields @timestamp, eventName, errorCode, sourceIPAddress, userIdentity.arn
| filter errorCode in ["AccessDenied", "UnauthorizedAccess", "Client.UnauthorizedAccess"]
| sort @timestamp desc
| limit 50
```

#### Step 2: Analyze the Source

Determine whether the unauthorized calls are:

| Source Type | Likely Cause | Action |
|---|---|---|
| GitLab instance role (`modules/gitlab/iam.tf`) | IAM policy too restrictive or GitLab attempting an action outside its scope | Review and update IAM policy in Terraform; this is usually a configuration issue, not an incident |
| Unknown IAM user or role | Potential compromised credentials | Escalate to SEV-2; deactivate credentials; investigate source IP |
| Root account | Root account usage (should never occur in production) | Escalate to SEV-1; investigate immediately; root usage in production is always a security concern |
| AWS service (e.g., `config.amazonaws.com`) | Service-linked role permission issue | Review service configuration; typically not a security incident |

#### Step 3: Determine if Malicious

Indicators of malicious unauthorized API calls:

- Source IP is not from known corporate or AWS service ranges
- API calls are reconnaissance-oriented (`Describe*`, `List*`, `Get*` across many services)
- Calls are made outside business hours
- The IAM entity does not correspond to known personnel or automation
- Multiple different API actions are attempted in rapid succession (enumeration pattern)

#### Step 4: Respond Based on Assessment

**If benign** (e.g., IAM policy needs update):

1. Document the finding
2. Create a Terraform change to update the IAM policy
3. Run `terraform plan` and `terraform apply`
4. Monitor for resolution of the alarm

**If suspicious or malicious**:

1. Assign severity per Section 3
2. Follow containment procedures in Section 5
3. Deactivate the affected IAM credentials
4. Review all API calls made by the entity in the last 7 days
5. Check for persistence mechanisms (new IAM users, roles, policies, Lambda functions, EC2 instances)
6. Report per Section 9

#### Step 5: Tune the Alarm

If the alarm generates excessive false positives from known benign sources:

1. Update the CloudWatch metric filter to exclude specific known-benign patterns
2. Document the exclusion in the Terraform code with an inline comment
3. Never broadly suppress unauthorized API call monitoring -- only exclude specific, documented patterns

### B.4 Common Benign Scenarios

| Scenario | Typical Error | Resolution |
|---|---|---|
| GitLab backup job attempting S3 cross-region replication check | `AccessDenied` on `s3:GetReplicationConfiguration` | Add permission to IAM policy in `modules/gitlab/iam.tf` |
| CloudWatch agent attempting to describe instances | `AccessDenied` on `ec2:DescribeInstances` | Add permission to IAM policy |
| SSM agent startup | `AccessDenied` on various SSM API calls | Verify SSM VPC endpoint and IAM policy |
| Config rule evaluation | `AccessDenied` on `config:PutEvaluations` | Review Config service-linked role |

---

*This document satisfies NIST 800-53 Rev 5 controls IR-1, IR-4, IR-5, IR-6, and IR-8 for the self-hosted GitLab CE on AWS deployment. It must be reviewed and updated annually, after any significant incident, or when the system architecture changes.*
