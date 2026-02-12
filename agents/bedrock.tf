resource "aws_bedrockagent_agent" "jira_processor" {
  agent_name                  = "mavis-jira-processor"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.foundation_model
  instruction                 = file("instructions/agent_base.md")
  idle_session_ttl_in_seconds = 900
}

resource "aws_bedrockagent_agent_action_group" "jira" {
  agent_id          = aws_bedrockagent_agent.jira_processor.id
  agent_version     = "DRAFT"
  action_group_name = "jira-query"
  description       = "Query JIRA tickets using the REST API"

  action_group_executor {
    lambda = aws_lambda_function.jira_query.arn
  }

  api_schema {
    payload = file("resources/jira_action_group_schema.json")
  }
}

resource "aws_bedrockagent_agent_action_group" "slack" {
  agent_id          = aws_bedrockagent_agent.jira_processor.id
  agent_version     = "DRAFT"
  action_group_name = "slack-notify"
  description       = "Send messages to Slack via incoming webhook"

  action_group_executor {
    lambda = aws_lambda_function.slack_notify.arn
  }

  api_schema {
    payload = file("resources/slack_action_group_schema.json")
  }
}

resource "aws_bedrockagent_agent_alias" "main" {
  agent_id         = aws_bedrockagent_agent.jira_processor.id
  agent_alias_name = "main"
}
