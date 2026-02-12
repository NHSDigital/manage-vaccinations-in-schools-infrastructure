resource "aws_ssm_parameter" "jira_token" {
  name        = "/agents/jira-api-token"
  description = "JIRA API token for Bedrock agent JIRA integration"
  type        = "SecureString"
  value       = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "slack_webhook_url" {
  name        = "/agents/slack-webhook-url/mavis-releases"
  description = "Slack incoming webhook URL for agent release notifications"
  type        = "SecureString"
  value       = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}
