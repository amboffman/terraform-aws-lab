# Phase 2: a serverless API.
#
#   Browser or curl  ->  API Gateway (HTTP API)  ->  Lambda (Python)  ->  DynamoDB
#
# Everything here bills per request, so it costs nothing while idle. There is
# no VPC, no NAT Gateway and no RDS in this file on purpose.
#
# Read this file top to bottom before you apply it. Each block has a comment
# that says what it is and why it is there. Those comments are your interview
# answers.

# ---------------------------------------------------------------------------
# 1. Data: DynamoDB table
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "notes" {
  name = "${var.project}-notes"

  # On-demand billing: pay per read and write, nothing while idle.
  # The alternative is PROVISIONED, where you reserve capacity (cheaper at
  # steady high traffic, wasteful for a lab).
  billing_mode = "PAY_PER_REQUEST"

  # The partition key. DynamoDB only needs you to declare key attributes;
  # every other attribute is schemaless.
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# 2. Permissions: the role the Lambda function runs as
# ---------------------------------------------------------------------------

# Trust policy: WHO may assume this role. Only the Lambda service.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "${var.project}-api-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permissions policy: WHAT the role may do. Least privilege: two DynamoDB
# actions on this one table, and writing logs to this one log group.
# Compare with attaching AmazonDynamoDBFullAccess, which would let the
# function delete any table in the account.
data "aws_iam_policy_document" "api" {
  statement {
    sid       = "NotesTable"
    actions   = ["dynamodb:PutItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.notes.arn]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }
}

resource "aws_iam_role_policy" "api" {
  name   = "notes-table-and-logs"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api.json
}

# ---------------------------------------------------------------------------
# 3. Compute: the Lambda function
# ---------------------------------------------------------------------------

# Zips the lambda/ folder at plan time. When handler.py changes, the hash
# changes, and Terraform knows to upload new code.
data "archive_file" "api" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.build/api.zip"
}

# Creating the log group here (instead of letting Lambda create it) means
# Terraform owns it: it gets a retention period and is removed on destroy.
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${var.project}-api"
  retention_in_days = 7
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project}-api"
  role          = aws_iam_role.api.arn

  runtime = "python3.13"
  handler = "handler.lambda_handler" # file handler.py, function lambda_handler

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  memory_size = 128
  timeout     = 5

  # Configuration goes in through environment variables, so the same code
  # works in any environment without edits.
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.notes.name
    }
  }

  # Make sure the log group and permissions exist before the function does.
  depends_on = [
    aws_cloudwatch_log_group.api,
    aws_iam_role_policy.api,
  ]
}

# ---------------------------------------------------------------------------
# 4. Front door: API Gateway HTTP API
# ---------------------------------------------------------------------------

# HTTP API is the newer, cheaper, simpler API Gateway type. REST API is the
# older one with more features (usage plans, API keys, request validation).
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  # Lets the CloudFront site (a different origin) call this API from the
  # browser. Open to all origins for the lab. In production you would list
  # the site's domain only.
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

# Integration: how API Gateway hands a request to the backend.
# AWS_PROXY passes the whole HTTP request to Lambda as one JSON event.
resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

# Routes: which method and path go to which integration.
# for_each creates one route per item in the set.
resource "aws_apigatewayv2_route" "api" {
  for_each = toset(["GET /notes", "POST /notes"])

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

# Stage: a deployed version of the API. "$default" with auto_deploy gives a
# clean URL with no stage name in the path.
resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # This URL is public. Throttling caps how fast anyone can call it, which
  # caps what a stranger could cost you.
  default_route_settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }
}

# Resource-based policy on the function: allows THIS API to invoke it.
# Note the two halves of Lambda permissions: the role (section 2) is what the
# function can do, and this is who can call the function.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ---------------------------------------------------------------------------
# 5. Monitoring: alarm when the function throws errors
# ---------------------------------------------------------------------------

# Goes to ALARM if the function errors at all within 5 minutes. No
# notification is wired up; in production alarm_actions would point at an
# SNS topic that pages someone.
resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name        = "${var.project}-api-errors"
  alarm_description = "Lambda API returned at least one error in 5 minutes"

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "api_url" {
  description = "Base URL of the API. Try GET and POST on /notes."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "api_log_group" {
  description = "CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.api.name
}
