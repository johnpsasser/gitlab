"""Secrets Manager rotation handler for GitLab root password (IA-5(1)).

Implements the standard 4-step rotation pattern:
  1. createSecret  - Generate new password, store as AWSPENDING
  2. setSecret     - Apply password on GitLab EC2 via SSM Run Command
  3. testSecret    - Verify the new password works via rails runner
  4. finishSecret  - Move AWSPENDING to AWSCURRENT

Password is passed to EC2 via a temporary SSM SecureString parameter
(never in shell arguments) and cleaned up in a finally block.
"""

import json
import logging
import os
import secrets
import string
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sm_client = boto3.client("secretsmanager")
ssm_client = boto3.client("ssm")

INSTANCE_ID = os.environ["GITLAB_INSTANCE_ID"]
PROJECT_NAME = os.environ["PROJECT_NAME"]
SSM_PARAM_PREFIX = f"/{PROJECT_NAME}/rotation"


def generate_password(length=24):
    """Generate a secure password meeting GitLab's 15-char minimum."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    while True:
        password = "".join(secrets.choice(alphabet) for _ in range(length))
        # Ensure complexity: at least one of each class
        if (any(c in string.ascii_lowercase for c in password)
                and any(c in string.ascii_uppercase for c in password)
                and any(c in string.digits for c in password)
                and any(c in "!@#$%^&*" for c in password)):
            return password


def run_command_on_instance(command, timeout_seconds=120):
    """Execute a shell command on the GitLab EC2 instance via SSM."""
    response = ssm_client.send_command(
        InstanceIds=[INSTANCE_ID],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [command]},
        TimeoutSeconds=timeout_seconds,
    )
    command_id = response["Command"]["CommandId"]

    # Poll for completion
    for _ in range(timeout_seconds // 5):
        time.sleep(5)
        result = ssm_client.get_command_invocation(
            CommandId=command_id,
            InstanceId=INSTANCE_ID,
        )
        if result["Status"] in ("Success", "Failed", "TimedOut", "Cancelled"):
            break

    if result["Status"] != "Success":
        raise RuntimeError(
            f"SSM command failed (status={result['Status']}): "
            f"{result.get('StandardErrorContent', 'no stderr')}"
        )
    return result.get("StandardOutputContent", "")


def create_secret(arn, token):
    """Step 1: Generate a new password and store it as AWSPENDING."""
    # Check if AWSPENDING already exists
    try:
        sm_client.get_secret_value(SecretId=arn, VersionId=token,
                                   VersionStage="AWSPENDING")
        logger.info("createSecret: AWSPENDING version already exists")
        return
    except sm_client.exceptions.ResourceNotFoundException:
        pass

    new_password = generate_password()
    sm_client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=new_password,
        VersionStages=["AWSPENDING"],
    )
    logger.info("createSecret: new password stored as AWSPENDING")


def set_secret(arn, token):
    """Step 2: Apply the new password on the GitLab instance via SSM."""
    # Retrieve the pending password
    response = sm_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )
    new_password = response["SecretString"]

    # Store password in a temporary SSM SecureString parameter
    param_name = f"{SSM_PARAM_PREFIX}/pending-password"
    try:
        ssm_client.put_parameter(
            Name=param_name,
            Value=new_password,
            Type="SecureString",
            Overwrite=True,
        )

        # Use gitlab-rails runner to set the password, reading from SSM param
        command = (
            f'NEW_PASS=$(aws ssm get-parameter --name "{param_name}" '
            f'--with-decryption --query Parameter.Value --output text) && '
            f'gitlab-rails runner "'
            f"user = User.find_by_username('root'); "
            f"user.password = ENV.fetch('NEW_PASS') {{ STDIN.read.chomp }}; "
            f"user.password_confirmation = user.password; "
            f'user.save!"'
            f' <<< "$NEW_PASS"'
        )
        run_command_on_instance(command)
        logger.info("setSecret: password updated on GitLab instance")
    finally:
        # Always clean up the temporary parameter
        try:
            ssm_client.delete_parameter(Name=param_name)
            logger.info("setSecret: cleaned up temporary SSM parameter")
        except Exception:
            logger.warning("setSecret: failed to clean up SSM parameter %s",
                           param_name)


def test_secret(arn, token):
    """Step 3: Verify the new password works on GitLab."""
    response = sm_client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage="AWSPENDING"
    )
    new_password = response["SecretString"]

    # Store password in temporary SSM parameter for verification
    param_name = f"{SSM_PARAM_PREFIX}/test-password"
    try:
        ssm_client.put_parameter(
            Name=param_name,
            Value=new_password,
            Type="SecureString",
            Overwrite=True,
        )

        command = (
            f'TEST_PASS=$(aws ssm get-parameter --name "{param_name}" '
            f'--with-decryption --query Parameter.Value --output text) && '
            f'gitlab-rails runner "'
            f"user = User.find_by_username('root'); "
            f"result = user.valid_password?(STDIN.read.chomp); "
            f"abort('Password verification failed') unless result; "
            f"puts 'Password verified successfully'"
            f'" <<< "$TEST_PASS"'
        )
        output = run_command_on_instance(command)
        if "Password verified successfully" not in output:
            raise RuntimeError(f"Password verification failed: {output}")
        logger.info("testSecret: new password verified successfully")
    finally:
        try:
            ssm_client.delete_parameter(Name=param_name)
        except Exception:
            logger.warning("testSecret: failed to clean up SSM parameter %s",
                           param_name)


def finish_secret(arn, token):
    """Step 4: Finalize rotation -- move AWSPENDING to AWSCURRENT."""
    # Determine the current version
    metadata = sm_client.describe_secret(SecretId=arn)
    for version_id, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages and version_id != token:
            # Move AWSCURRENT to AWSPREVIOUS and AWSPENDING to AWSCURRENT
            sm_client.update_secret_version_stage(
                SecretId=arn,
                VersionStage="AWSCURRENT",
                MoveToVersionId=token,
                RemoveFromVersionId=version_id,
            )
            logger.info("finishSecret: rotation complete, AWSPENDING is now AWSCURRENT")
            return

    logger.info("finishSecret: version %s is already AWSCURRENT", token)


def lambda_handler(event, context):
    """Secrets Manager rotation handler entry point."""
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    # Verify the secret exists and this version is staged correctly
    metadata = sm_client.describe_secret(SecretId=arn)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {arn} does not have rotation enabled")

    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        raise ValueError(f"Secret version {token} has no stage for secret {arn}")

    if "AWSCURRENT" in versions.get(token, []):
        logger.info("Secret version %s is already AWSCURRENT", token)
        return

    if "AWSPENDING" not in versions.get(token, []):
        raise ValueError(f"Secret version {token} not set as AWSPENDING for {arn}")

    steps = {
        "createSecret": create_secret,
        "setSecret": set_secret,
        "testSecret": test_secret,
        "finishSecret": finish_secret,
    }

    if step not in steps:
        raise ValueError(f"Invalid step: {step}")

    steps[step](arn, token)
