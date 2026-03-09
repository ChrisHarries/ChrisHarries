"""
Secrets Manager rotation handler for Datadog API keys.

Implements the four-stage rotation lifecycle required by AWS Secrets Manager:
  createSecret  – generate a new Datadog API key
  setSecret     – store it in the AWSPENDING staging label
  testSecret    – validate the new key works against Datadog
  finishSecret  – promote AWSPENDING to AWSCURRENT, revoke the old key
"""

import json
import logging
import os
import urllib.request
import urllib.error

logger = logging.getLogger()
logger.setLevel(logging.INFO)

import boto3

sm = boto3.client("secretsmanager")


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    metadata = sm.describe_secret(SecretId=arn)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {arn} does not have rotation enabled")

    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        raise ValueError(f"Token {token} not found in secret versions")

    if "AWSCURRENT" in versions[token]:
        logger.info("Token already AWSCURRENT — nothing to do")
        return
    if "AWSPENDING" not in versions[token] and step != "createSecret":
        raise ValueError(f"Token {token} is not AWSPENDING")

    if step == "createSecret":
        create_secret(arn, token)
    elif step == "setSecret":
        set_secret(arn, token)
    elif step == "testSecret":
        test_secret(arn, token)
    elif step == "finishSecret":
        finish_secret(arn, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_dd_site():
    return os.environ.get("DD_SITE", "datadoghq.com")


def _datadog_request(path, method="GET", body=None, api_key=None, app_key=None):
    """Make an authenticated request to the Datadog API v2."""
    site = _get_dd_site()
    url = f"https://api.{site}{path}"
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["DD-API-KEY"] = api_key
    if app_key:
        headers["DD-APPLICATION-KEY"] = app_key

    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Datadog API {method} {path} returned {exc.code}: {exc.read().decode()}") from exc


def _get_secret_value(arn, stage):
    resp = sm.get_secret_value(SecretId=arn, VersionStage=stage)
    return json.loads(resp["SecretString"])


def _get_app_key(secret):
    """Extract the Datadog APP key from the secret payload (used to manage API keys)."""
    app_key = secret.get("app_key") or secret.get("DD_APP_KEY")
    if not app_key:
        raise KeyError("app_key not found in secret payload")
    return app_key


# ---------------------------------------------------------------------------
# Rotation stages
# ---------------------------------------------------------------------------

def create_secret(arn, token):
    """Create a new Datadog API key and store it as AWSPENDING."""
    try:
        sm.get_secret_value(SecretId=arn, VersionStage="AWSPENDING", VersionId=token)
        logger.info("AWSPENDING already exists — skipping createSecret")
        return
    except sm.exceptions.ResourceNotFoundException:
        pass

    current = _get_secret_value(arn, "AWSCURRENT")
    app_key = _get_app_key(current)
    current_api_key = current.get("api_key") or current.get("DD_API_KEY")

    key_name = os.environ.get("DD_KEY_NAME", f"rotated-key-{token[:8]}")
    result = _datadog_request(
        "/api/v2/api_keys",
        method="POST",
        body={"data": {"type": "api_keys", "attributes": {"name": key_name}}},
        api_key=current_api_key,
        app_key=app_key,
    )
    new_api_key = result["data"]["attributes"]["key"]
    new_key_id = result["data"]["id"]

    new_secret = dict(current)
    new_secret["api_key"] = new_api_key
    new_secret["DD_API_KEY"] = new_api_key
    new_secret["_pending_key_id"] = new_key_id

    sm.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(new_secret),
        VersionStages=["AWSPENDING"],
    )
    logger.info("Created new Datadog API key and stored as AWSPENDING")


def set_secret(arn, token):
    """Nothing extra needed — key was already stored in createSecret."""
    logger.info("setSecret: no additional action required")


def test_secret(arn, token):
    """Validate the new API key by calling the Datadog validate endpoint."""
    pending = _get_secret_value(arn, "AWSPENDING")
    new_api_key = pending.get("api_key") or pending.get("DD_API_KEY")
    app_key = _get_app_key(pending)

    _datadog_request("/api/v2/validate", api_key=new_api_key, app_key=app_key)
    logger.info("New Datadog API key validated successfully")


def finish_secret(arn, token):
    """Promote AWSPENDING to AWSCURRENT and revoke the old API key."""
    metadata = sm.describe_secret(SecretId=arn)
    current_version = next(
        vid
        for vid, stages in metadata["VersionIdsToStages"].items()
        if "AWSCURRENT" in stages
    )

    if current_version == token:
        logger.info("Token is already AWSCURRENT — nothing to do")
        return

    # Retrieve old key id before promoting
    old_secret = _get_secret_value(arn, "AWSCURRENT")
    new_secret = _get_secret_value(arn, "AWSPENDING")
    app_key = _get_app_key(new_secret)
    new_api_key = new_secret.get("api_key") or new_secret.get("DD_API_KEY")

    sm.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("Promoted AWSPENDING to AWSCURRENT")

    # Revoke the OLD key using the new (now current) credentials
    old_key_id = _find_key_id(old_secret.get("api_key") or old_secret.get("DD_API_KEY"), new_api_key, app_key)
    if old_key_id:
        _datadog_request(f"/api/v2/api_keys/{old_key_id}", method="DELETE", api_key=new_api_key, app_key=app_key)
        logger.info(f"Revoked old Datadog API key {old_key_id}")
    else:
        logger.warning("Could not find old API key to revoke — it may have already been removed")


def _find_key_id(old_api_key_value, current_api_key, app_key):
    """Look up the Datadog key ID for a given key value by listing all keys."""
    if not old_api_key_value:
        return None
    try:
        result = _datadog_request(
            "/api/v2/api_keys?filter[modified_after]=1970-01-01T00:00:00Z",
            api_key=current_api_key,
            app_key=app_key,
        )
        for item in result.get("data", []):
            if item["attributes"].get("last4") and old_api_key_value.endswith(item["attributes"]["last4"]):
                return item["id"]
    except Exception as exc:
        logger.warning(f"Could not list Datadog API keys: {exc}")
    return None
