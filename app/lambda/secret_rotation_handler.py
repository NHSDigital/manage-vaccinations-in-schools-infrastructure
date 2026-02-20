import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ECS_CLUSTER = os.environ["ECS_CLUSTER"]
SERVICE_NAMES = json.loads(os.environ["SERVICE_NAMES"])


def lambda_handler(event, context):
    logger.info("Received secret rotation event: %s", json.dumps(event))

    ecs = boto3.client("ecs")
    results = {}

    for service_name in SERVICE_NAMES:
        try:
            response = ecs.update_service(
                cluster=ECS_CLUSTER,
                service=service_name,
                forceNewDeployment=True,
            )
            running_count = response["service"]["runningCount"]
            results[service_name] = {
                "status": "redeployed",
                "runningCount": running_count,
            }
            logger.info(
                "Forced redeployment of %s (running: %d)",
                service_name,
                running_count,
            )
        except ecs.exceptions.ServiceNotFoundException:
            results[service_name] = {"status": "not_found"}
            logger.warning("Service %s not found, skipping", service_name)
        except Exception as e:
            results[service_name] = {"status": "error", "error": str(e)}
            logger.error("Failed to redeploy %s: %s", service_name, str(e))

    logger.info("Redeployment results: %s", json.dumps(results))

    errors = {k: v for k, v in results.items() if v["status"] == "error"}
    if errors:
        raise RuntimeError(f"Failed to redeploy services: {json.dumps(errors)}")

    return results
