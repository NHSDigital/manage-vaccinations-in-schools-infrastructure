output "agent_id" {
  description = "The ID of the Bedrock agent"
  value       = aws_bedrockagent_agent.jira_processor.agent_id
}

output "agent_alias_id" {
  description = "The alias ID of the Bedrock agent"
  value       = aws_bedrockagent_agent_alias.main.agent_alias_id
}
