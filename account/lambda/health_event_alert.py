# AWS Lambda function to send AWS Health Event alerts to Slack
#
# This function is triggered by EventBridge when AWS Health events occur.
# It reads the Slack webhook URL from SSM Parameter Store at runtime and
# posts a formatted message to Slack.

import json
import os
import logging

import boto3
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENVIRONMENT = os.getenv("ENVIRONMENT")
SSM_PARAMETER_NAME = os.getenv("SSM_PARAMETER_NAME")

ssm_client = boto3.client("ssm")


def get_slack_webhook_url():
    response = ssm_client.get_parameter(
        Name=SSM_PARAMETER_NAME, WithDecryption=True
    )
    return response["Parameter"]["Value"]


def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    detail = event.get("detail", {})
    detail_type = event.get("detail-type", "AWS Health Event")
    service = detail.get("service", "Unknown")
    event_type_code = detail.get("eventTypeCode", "Unknown")
    event_type_category = detail.get("eventTypeCategory", "Unknown")
    region = event.get("region", "Unknown")
    start_time = detail.get("startTime", "Unknown")
    description = ""

    event_description = detail.get("eventDescription", [])
    if event_description:
        description = event_description[0].get("latestDescription", "")

    affected_entities = detail.get("affectedEntities", [])
    entity_values = [e.get("entityValue", "") for e in affected_entities]

    slack_message = {
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"AWS Health Event - {ENVIRONMENT}",
                },
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": f"*Event*\n{detail_type}"},
                    {"type": "mrkdwn", "text": f"*Service*\n{service}"},
                    {"type": "mrkdwn", "text": f"*Type*\n{event_type_code}"},
                    {"type": "mrkdwn", "text": f"*Category*\n{event_type_category}"},
                    {"type": "mrkdwn", "text": f"*Region*\n{region}"},
                    {"type": "mrkdwn", "text": f"*Start Time*\n{start_time}"},
                ],
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Description*\n{description[:2000]}"
                    if description
                    else "*Description*\nNo description available.",
                },
            },
        ]
    }

    if entity_values:
        slack_message["blocks"].append(
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Affected Resources*\n{', '.join(entity_values[:10])}",
                },
            }
        )

    slack_message["blocks"].append(
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "<https://health.aws.amazon.com/health/home|View AWS Health Dashboard>",
                }
            ],
        }
    )

    slack_webhook_url = get_slack_webhook_url()
    req = Request(slack_webhook_url, json.dumps(slack_message).encode("utf-8"))
    req.add_header("Content-Type", "application/json")

    try:
        response = urlopen(req)
        response.read()
        logger.info("Message posted to Slack successfully.")
    except HTTPError as e:
        logger.error("Request failed: %d %s", e.code, e.reason)
    except URLError as e:
        logger.error("Server connection failed: %s", e.reason)
