"""CISA Known Exploited Vulnerabilities (KEV) monitoring Lambda (SI-5).

Polls the CISA KEV catalog daily, compares against the last known state
stored in DynamoDB, and sends SNS notifications for new entries.
"""

import json
import logging
import os
import ssl
import urllib.request
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sns_client = boto3.client("sns")

CISA_KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
STATE_KEY = "cisa-kev-latest"


def fetch_kev_catalog():
    """Fetch the CISA KEV JSON catalog."""
    ctx = ssl.create_default_context()
    req = urllib.request.Request(CISA_KEV_URL, headers={"User-Agent": "AWS-Lambda-CISA-Monitor/1.0"})
    with urllib.request.urlopen(req, context=ctx, timeout=60) as resp:
        return json.loads(resp.read().decode())


def get_known_cve_ids(table):
    """Retrieve all known CVE IDs from DynamoDB."""
    response = table.get_item(Key={"id": STATE_KEY})
    item = response.get("Item")
    if item:
        known_ids = item.get("known_cve_ids", "[]")
        return set(json.loads(known_ids))
    return None


def save_state(table, known_cve_ids, latest_cve):
    """Save current KEV state to DynamoDB."""
    table.put_item(Item={
        "id": STATE_KEY,
        "vulnerability_count": len(known_cve_ids),
        "known_cve_ids": json.dumps(sorted(known_cve_ids)),
        "latest_cve": latest_cve,
        "last_checked": datetime.now(timezone.utc).isoformat(),
    })


def lambda_handler(event, context):
    """Main handler: check for new CISA KEV entries."""
    table_name = os.environ["DYNAMODB_TABLE"]
    sns_topic_arn = os.environ["SNS_TOPIC_ARN"]

    table = dynamodb.Table(table_name)

    logger.info("Fetching CISA KEV catalog from %s", CISA_KEV_URL)
    catalog = fetch_kev_catalog()

    vulnerabilities = catalog.get("vulnerabilities", [])
    current_count = len(vulnerabilities)
    catalog_version = catalog.get("catalogVersion", "unknown")
    date_released = catalog.get("dateReleased", "unknown")

    # Sort by dateAdded descending to find newest entries
    vulnerabilities.sort(key=lambda v: v.get("dateAdded", ""), reverse=True)
    latest_cve = vulnerabilities[0]["cveID"] if vulnerabilities else ""

    logger.info("KEV catalog: %d vulnerabilities, version=%s, released=%s, latest=%s",
                current_count, catalog_version, date_released, latest_cve)

    all_cve_ids = {v["cveID"] for v in vulnerabilities}
    known_ids = get_known_cve_ids(table)

    if known_ids is None:
        # First run -- save baseline state
        save_state(table, all_cve_ids, latest_cve)
        logger.info("First run: saved baseline state (%d vulnerabilities)", current_count)

        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject="CISA KEV Monitor: Baseline Established",
            Message=(
                f"CISA KEV monitoring initialized.\n\n"
                f"Current catalog: {current_count} vulnerabilities\n"
                f"Catalog version: {catalog_version}\n"
                f"Latest CVE: {latest_cve}\n"
            ),
        )
        return {"status": "baseline_established", "count": len(all_cve_ids)}

    new_cve_ids = all_cve_ids - known_ids

    if new_cve_ids:
        new_entries = [v for v in vulnerabilities if v["cveID"] in new_cve_ids]

        subject = f"CISA KEV Alert: {len(new_cve_ids)} new vulnerabilities added"
        message = (
            f"{len(new_cve_ids)} new vulnerabilities added to the CISA KEV catalog.\n\n"
            f"Catalog version: {catalog_version}\n"
            f"Total vulnerabilities: {current_count}\n\n"
            f"New entries:\n"
        )
        for entry in new_entries:
            message += (
                f"\n  CVE: {entry.get('cveID', 'N/A')}\n"
                f"  Vendor: {entry.get('vendorProject', 'N/A')}\n"
                f"  Product: {entry.get('product', 'N/A')}\n"
                f"  Name: {entry.get('vulnerabilityName', 'N/A')}\n"
                f"  Date Added: {entry.get('dateAdded', 'N/A')}\n"
                f"  Due Date: {entry.get('dueDate', 'N/A')}\n"
                f"  Action: {entry.get('requiredAction', 'N/A')}\n"
            )

        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=subject[:100],
            Message=message,
        )
        logger.info("SNS notification sent: %d new KEV entries", len(new_cve_ids))

    else:
        logger.info("No new KEV entries since last check")

    # Update state with all known IDs
    save_state(table, all_cve_ids, latest_cve)

    return {
        "status": "checked",
        "previous_count": len(known_ids),
        "current_count": len(all_cve_ids),
        "new_entries": len(new_cve_ids) if new_cve_ids else 0,
    }
