### SSM Parameter for Slack Webhook URL ###
# The value is set manually and ignored by Terraform after creation.

resource "aws_ssm_parameter" "slack_webhook_url" {
  name        = "/mavis/${var.environment}/health-events/slack-webhook-url"
  description = "Slack webhook URL for AWS Health Event notifications"
  type        = "SecureString"
  value       = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }
}

### Lambda function ###

data "archive_file" "health_event_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/health_event_alert.py"
  output_path = "${path.module}/lambda/health_event_alert_function.zip"
}

resource "aws_lambda_function" "health_event_alert" {
  filename         = data.archive_file.health_event_lambda_zip.output_path
  function_name    = "health_event_alert"
  description      = "Sends AWS Health Event notifications to Slack"
  role             = aws_iam_role.health_event_lambda_execution.arn
  handler          = "health_event_alert.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.health_event_lambda_zip.output_base64sha256

  environment {
    variables = {
      SSM_PARAMETER_NAME = aws_ssm_parameter.slack_webhook_url.name
      ENVIRONMENT        = var.environment
    }
  }
}

### EventBridge rule ###

resource "aws_cloudwatch_event_rule" "health_events" {
  name        = "aws-health-events"
  description = "Captures AWS Health events"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

resource "aws_cloudwatch_event_target" "health_event_lambda" {
  rule      = aws_cloudwatch_event_rule.health_events.name
  target_id = "health-event-alert-lambda"
  arn       = aws_lambda_function.health_event_alert.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.health_event_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_events.arn
}
