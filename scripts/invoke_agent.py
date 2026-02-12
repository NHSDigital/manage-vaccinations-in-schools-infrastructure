#!/usr/bin/env python3
"""Invoke a Bedrock agent and print the response to stdout."""

import argparse
import sys
import uuid

import boto3


def invoke_agent(agent_id: str, agent_alias_id: str, prompt: str) -> str:
    client = boto3.client("bedrock-agent-runtime", region_name="eu-west-2")
    session_id = str(uuid.uuid4())

    response = client.invoke_agent(
        agentId=agent_id,
        agentAliasId=agent_alias_id,
        sessionId=session_id,
        inputText=prompt,
    )

    output_parts = []
    for event in response["completion"]:
        if "chunk" in event:
            output_parts.append(event["chunk"]["bytes"].decode("utf-8"))

    return "".join(output_parts)


def main():
    parser = argparse.ArgumentParser(description="Invoke a Bedrock agent")
    parser.add_argument("--agent-id", required=True, help="Bedrock agent ID")
    parser.add_argument(
        "--agent-alias-id", required=True, help="Bedrock agent alias ID"
    )
    parser.add_argument("--prompt", required=True, help="Prompt text for the agent")
    args = parser.parse_args()

    try:
        result = invoke_agent(args.agent_id, args.agent_alias_id, args.prompt)
        print(result)
    except Exception as e:
        print(f"Error invoking agent: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
