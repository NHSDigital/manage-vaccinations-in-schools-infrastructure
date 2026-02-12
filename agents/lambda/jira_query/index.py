"""Lambda function for Bedrock Agent action group to query JIRA REST API."""

import json
import os
import re
import urllib.request
import urllib.error
import urllib.parse

import boto3

ssm_client = boto3.client("ssm")
_jira_token_cache = None


def get_jira_token():
    global _jira_token_cache
    if _jira_token_cache is None:
        response = ssm_client.get_parameter(
            Name=os.environ["JIRA_TOKEN_SSM_NAME"], WithDecryption=True
        )
        _jira_token_cache = response["Parameter"]["Value"]
    return _jira_token_cache


def jira_request(path, params=None):
    base_url = os.environ["JIRA_BASE_URL"].rstrip("/")
    url = f"{base_url}/rest/api/3/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)

    token = get_jira_token()
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/json")

    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else ""
        return {"error": f"HTTP {e.code}: {body}"}


def search_tickets(jql, max_results=50):
    data = jira_request(
        "search", {"jql": jql, "maxResults": max_results, "fields": "summary,status,assignee,created,updated,description"}
    )
    if "error" in data:
        return data

    issues = []
    for issue in data.get("issues", []):
        fields = issue.get("fields", {})
        assignee = fields.get("assignee")
        issues.append(
            {
                "key": issue["key"],
                "summary": fields.get("summary", ""),
                "status": fields.get("status", {}).get("name", ""),
                "assignee": assignee.get("displayName", "") if assignee else "Unassigned",
                "created": fields.get("created", ""),
                "updated": fields.get("updated", ""),
                "description": _extract_text(fields.get("description")),
            }
        )
    return {"total": data.get("total", 0), "issues": issues}


def get_ticket(ticket_key):
    data = jira_request(f"issue/{ticket_key}")
    if "error" in data:
        return data

    fields = data.get("fields", {})
    assignee = fields.get("assignee")
    return {
        "key": data["key"],
        "summary": fields.get("summary", ""),
        "status": fields.get("status", {}).get("name", ""),
        "assignee": assignee.get("displayName", "") if assignee else "Unassigned",
        "created": fields.get("created", ""),
        "updated": fields.get("updated", ""),
        "description": _extract_text(fields.get("description")),
        "labels": fields.get("labels", []),
        "priority": fields.get("priority", {}).get("name", ""),
    }


def get_ticket_comments(ticket_key):
    data = jira_request(f"issue/{ticket_key}/comment")
    if "error" in data:
        return data

    comments = []
    for comment in data.get("comments", []):
        comments.append(
            {
                "author": comment.get("author", {}).get("displayName", "Unknown"),
                "created": comment.get("created", ""),
                "body": _extract_text(comment.get("body")),
            }
        )
    return {"comments": comments}


def get_latest_release_tickets():
    data = jira_request("project/MAV/versions")
    if isinstance(data, dict) and "error" in data:
        return data

    version_pattern = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
    versions = []
    for v in data:
        match = version_pattern.match(v.get("name", ""))
        if match:
            versions.append((int(match.group(1)), int(match.group(2)), int(match.group(3)), v["name"]))

    if not versions:
        return {"error": "No versions matching vX.Y.Z pattern found for project MAV"}

    versions.sort(reverse=True)
    latest_version = versions[0][3]

    jql = f'project = MAV AND fixVersion = "{latest_version}"'
    result = search_tickets(jql, max_results=200)
    result["version"] = latest_version
    return result


def _extract_text(adf_doc):
    """Extract plain text from Atlassian Document Format."""
    if adf_doc is None:
        return ""
    if isinstance(adf_doc, str):
        return adf_doc

    texts = []
    if isinstance(adf_doc, dict):
        if adf_doc.get("type") == "text":
            texts.append(adf_doc.get("text", ""))
        for child in adf_doc.get("content", []):
            texts.append(_extract_text(child))
    return " ".join(t for t in texts if t)


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

    if function == "searchTickets":
        jql = param_map.get("jql", "")
        max_results = int(param_map.get("maxResults", "50"))
        result = search_tickets(jql, max_results)
    elif function == "getTicket":
        ticket_key = param_map.get("ticketKey", "")
        result = get_ticket(ticket_key)
    elif function == "getTicketComments":
        ticket_key = param_map.get("ticketKey", "")
        result = get_ticket_comments(ticket_key)
    elif function == "getLatestReleaseTickets":
        result = get_latest_release_tickets()
    else:
        result = {"error": f"Unknown function: {function}"}

    return build_response(event, action_group, function, result)
