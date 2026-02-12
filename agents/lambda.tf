data "archive_file" "jira_query" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/jira_query"
  output_path = "${path.module}/lambda/jira_query.zip"
}

resource "aws_lambda_function" "jira_query" {
  function_name    = "mavis-jira-query"
  role             = aws_iam_role.lambda_agent.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.jira_query.output_path
  source_code_hash = data.archive_file.jira_query.output_base64sha256

  environment {
    variables = {
      JIRA_BASE_URL       = var.jira_base_url
      JIRA_TOKEN_SSM_NAME = aws_ssm_parameter.jira_token.name
    }
  }
}

resource "aws_lambda_permission" "bedrock_invoke" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.jira_query.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.jira_processor.agent_arn
}

resource "aws_cloudwatch_log_group" "jira_query" {
  name              = "/aws/lambda/${aws_lambda_function.jira_query.function_name}"
  retention_in_days = 30
}

################ Slack Notify Lambda ################

data "archive_file" "slack_notify" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/slack_notify"
  output_path = "${path.module}/lambda/slack_notify.zip"
}

resource "aws_lambda_function" "slack_notify" {
  function_name    = "mavis-slack-notify"
  role             = aws_iam_role.lambda_agent.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.slack_notify.output_path
  source_code_hash = data.archive_file.slack_notify.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_SSM_NAME = aws_ssm_parameter.slack_webhook_url.name
    }
  }
}

resource "aws_lambda_permission" "bedrock_invoke_slack" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notify.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.jira_processor.agent_arn
}

resource "aws_cloudwatch_log_group" "slack_notify" {
  name              = "/aws/lambda/${aws_lambda_function.slack_notify.function_name}"
  retention_in_days = 30
}
