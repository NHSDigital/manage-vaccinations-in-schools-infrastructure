################ Bedrock Agent Role ################

data "aws_iam_policy_document" "bedrock_agent_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "bedrock_agent" {
  statement {
    sid    = "InvokeModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [
      "arn:aws:bedrock:eu-west-2::foundation-model/${var.foundation_model}",
    ]
  }
}

resource "aws_iam_role" "bedrock_agent" {
  name               = "BedrockAgentRole"
  assume_role_policy = data.aws_iam_policy_document.bedrock_agent_trust.json
}

resource "aws_iam_role_policy" "bedrock_agent" {
  name   = "BedrockAgentPolicy"
  role   = aws_iam_role.bedrock_agent.id
  policy = data.aws_iam_policy_document.bedrock_agent.json
}

################ Lambda Execution Role ################

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_agent" {
  statement {
    sid    = "GetSSMParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      aws_ssm_parameter.jira_token.arn,
      aws_ssm_parameter.slack_webhook_url.arn,
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.jira_query.arn}:*",
      "${aws_cloudwatch_log_group.slack_notify.arn}:*",
    ]
  }
}

resource "aws_iam_role" "lambda_agent" {
  name               = "AgentLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy" "lambda_agent" {
  name   = "AgentLambdaPolicy"
  role   = aws_iam_role.lambda_agent.id
  policy = data.aws_iam_policy_document.lambda_agent.json
}
