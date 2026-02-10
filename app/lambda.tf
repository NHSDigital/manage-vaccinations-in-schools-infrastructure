################################# Secret Rotation ECS Redeploy #################################
# When the RDS master password is rotated via Secrets Manager, this Lambda
# forces a new deployment of all CORE ECS services so they pick up the new
# credentials without waiting for healthcheck-driven task replacement.

data "archive_file" "secret_rotation_handler" {
  type        = "zip"
  source_file = "${path.module}/lambda/secret_rotation_handler.py"
  output_path = "${path.module}/lambda/secret_rotation_handler_function.zip"
}

resource "aws_lambda_function" "secret_rotation_redeploy" {
  filename         = data.archive_file.secret_rotation_handler.output_path
  function_name    = "rds-secret-rotation-redeploy-${var.environment}"
  description      = "Redeploys CORE ECS services when the RDS master password is rotated"
  role             = aws_iam_role.secret_rotation_lambda.arn
  handler          = "secret_rotation_handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  source_code_hash = data.archive_file.secret_rotation_handler.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.cluster.name
      SERVICE_NAMES = jsonencode([
        module.web_service.service.name,
        module.sidekiq_service.service.name,
        module.ops_service.service.name,
      ])
    }
  }

  depends_on = [aws_cloudwatch_log_group.secret_rotation_lambda]
}

resource "aws_cloudwatch_event_rule" "rds_secret_rotation" {
  name        = "rds-secret-rotation-${var.environment}"
  description = "Triggers ECS redeployment when the RDS master password rotation succeeds"

  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS Service Event via CloudTrail"]
    detail = {
      eventName = ["RotationSucceeded"]
      additionalEventData = {
        SecretId = [aws_rds_cluster.core.master_user_secret[0].secret_arn]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "rds_secret_rotation" {
  rule = aws_cloudwatch_event_rule.rds_secret_rotation.name
  arn  = aws_lambda_function.secret_rotation_redeploy.arn
}

resource "aws_lambda_permission" "eventbridge_secret_rotation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotation_redeploy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_secret_rotation.arn
}
