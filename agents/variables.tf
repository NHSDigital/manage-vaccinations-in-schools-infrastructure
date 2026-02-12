variable "jira_base_url" {
  type        = string
  description = "Base URL for the JIRA/Atlassian instance (e.g. https://your-org.atlassian.net)."
  default     = "https://nhsd-jira.digital.nhs.uk"
  nullable    = false
}

variable "foundation_model" {
  type        = string
  description = "Bedrock foundation model ID for the agent."
  default     = "anthropic.claude-sonnet-4-20250514-v1:0"
  nullable    = false
}
