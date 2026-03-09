# terraform/modules/lambda/main.tf

# ── DynamoDB idempotency table ────────────────────────────────────────────────
resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.name_prefix}-lambda-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = var.tags
}

# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-lambda-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda own logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.name_prefix}-analyzer:*"
      },
      # App log group — read events
      {
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          var.log_group_arn,
          "${var.log_group_arn}:*",
        ]
      },
      # SNS publish
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      },
      # DynamoDB idempotency
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:ConditionCheckItem",
        ]
        Resource = aws_dynamodb_table.idempotency.arn
      },
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "analyzer" {
  function_name = "${var.name_prefix}-analyzer"
  filename      = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.11"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  tags          = var.tags

  environment {
    variables = {
      LOG_GROUP_NAME       = var.log_group_name
      SNS_TOPIC_ARN        = var.sns_topic_arn
      OLLAMA_URL           = var.ollama_url
      IDEMPOTENCY_TABLE_NAME = aws_dynamodb_table.idempotency.name
    }
  }
}

# ── CloudWatch Log Group for Lambda ──────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.analyzer.function_name}"
  retention_in_days = 7
  tags              = var.tags
}
