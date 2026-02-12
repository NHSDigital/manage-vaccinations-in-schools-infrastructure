"""Lambda function for Bedrock Agent action group to send Slack messages."""

import json
import os
import urllib.request
import urllib.error

import boto3

ssm_client = boto3.client("ssm")
_webhook_url_cache = None


def get_slack_webhook_url():
    global _webhook_url_cache
    if _webhook_url_cache is None:
        response = ssm_client.get_parameter(
            Name=os.environ["SLACK_WEBHOOK_SSM_NAME"], WithDecryption=True
        )
        _webhook_url_cache = response["Parameter"]["Value"]
    return _webhook_url_cache


def send_slack_message(message):
    webhook_url = get_slack_webhook_url()
    payload = json.dumps({"text": message}).encode("utf-8")

    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as resp:
            return {"ok": True}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else ""
        return {"error": f"HTTP {e.code}: {body}"}


def build_response(event, action_group, function, body):
    return {
        "messageVersion": event.get("messageVersion", "1.0"),
        "response": {
            "actionGroup": action_group,
            "function": function,
            "functionResponse": {
                "responseBody": {"TEXT": {"body": json.dumps(body)}},
            },
        },
    }


def handler(event, context):
    action_group = event.get("actionGroup", "")
    function = event.get("function", "")
    parameters = event.get("parameters", [])

    param_map = {p["name"]: p["value"] for p in parameters}

    if function == "sendSlackMessage":
        message = param_map.get("message", "")
        result = send_slack_message(message)
    else:
        result = {"error": f"Unknown function: {function}"}

    return build_response(event, action_group, function, result)
