"""Inactive GitLab User Deactivation Lambda (AC-2(3)).

Deactivates GitLab users inactive for more than INACTIVE_DAYS days.
Skips admin and bot accounts. Supports DRY_RUN mode.
"""

import json
import logging
import os
import ssl
import urllib.request
import urllib.parse
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secrets_client = boto3.client("secretsmanager")
sns_client = boto3.client("sns")


def get_gitlab_token():
    """Retrieve GitLab admin PAT from Secrets Manager."""
    secret_name = os.environ["SECRET_NAME"]
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return response["SecretString"].strip()


def gitlab_api(method, path, token, data=None):
    """Make a GitLab API request using urllib."""
    base_url = os.environ["GITLAB_URL"]
    url = f"{base_url}/api/v4{path}"
    headers = {"PRIVATE-TOKEN": token, "Content-Type": "application/json"}

    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)

    # Trust the ALB certificate
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        response_data = resp.read().decode()
        return json.loads(response_data) if response_data else None


def get_all_active_users(token):
    """Paginate through all active, non-bot, non-admin users."""
    users = []
    page = 1
    per_page = 100
    while True:
        path = f"/users?active=true&without_project_bots=true&page={page}&per_page={per_page}"
        page_users = gitlab_api("GET", path, token)
        if not page_users:
            break
        users.extend(page_users)
        if len(page_users) < per_page:
            break
        page += 1
    return users


def lambda_handler(event, context):
    """Main handler: find and deactivate inactive users."""
    inactive_days = int(os.environ.get("INACTIVE_DAYS", "90"))
    dry_run = os.environ.get("DRY_RUN", "true").lower() == "true"
    sns_topic_arn = os.environ["SNS_TOPIC_ARN"]

    logger.info("Starting user deactivation check (inactive_days=%d, dry_run=%s)",
                inactive_days, dry_run)

    token = get_gitlab_token()
    users = get_all_active_users(token)
    now = datetime.now(timezone.utc)
    deactivated = []

    for user in users:
        # Skip admin accounts
        if user.get("is_admin", False):
            logger.info("Skipping admin user: %s (id=%d)", user["username"], user["id"])
            continue

        # Skip bot accounts
        if user.get("bot", False):
            logger.info("Skipping bot user: %s (id=%d)", user["username"], user["id"])
            continue

        # Check last activity
        last_activity = user.get("last_activity_on")
        if not last_activity:
            logger.info("No activity recorded for user: %s (id=%d), skipping",
                        user["username"], user["id"])
            continue

        last_active = datetime.strptime(last_activity, "%Y-%m-%d").replace(
            tzinfo=timezone.utc
        )
        days_inactive = (now - last_active).days

        if days_inactive > inactive_days:
            if dry_run:
                logger.info("[DRY RUN] Would deactivate user: %s (id=%d, inactive %d days)",
                            user["username"], user["id"], days_inactive)
            else:
                try:
                    gitlab_api("POST", f"/users/{user['id']}/deactivate", token)
                    logger.info("Deactivated user: %s (id=%d, inactive %d days)",
                                user["username"], user["id"], days_inactive)
                except Exception:
                    logger.exception("Failed to deactivate user: %s (id=%d)",
                                     user["username"], user["id"])
                    continue
            deactivated.append({
                "username": user["username"],
                "id": user["id"],
                "days_inactive": days_inactive,
            })

    # Send SNS notification if any users were deactivated (or would be)
    if deactivated:
        action = "would deactivate (DRY RUN)" if dry_run else "deactivated"
        subject = f"GitLab User Deactivation: {len(deactivated)} users {action}"
        message = f"The following {len(deactivated)} users were {action}:\n\n"
        for u in deactivated:
            message += f"  - {u['username']} (id={u['id']}, inactive {u['days_inactive']} days)\n"

        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=subject[:100],
            Message=message,
        )
        logger.info("SNS notification sent: %d users %s", len(deactivated), action)

    result = {
        "total_active_users": len(users),
        "users_deactivated": len(deactivated),
        "dry_run": dry_run,
        "inactive_threshold_days": inactive_days,
    }
    logger.info("Completed: %s", json.dumps(result))
    return result
