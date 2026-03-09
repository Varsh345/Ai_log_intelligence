# terraform/modules/cloudwatch/main.tf

# ── Metric Filter ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "error_warn" {
  name           = "${var.name_prefix}-error-warn-filter"
  log_group_name = var.log_group_name
  pattern        = "?ERROR ?WARN"

  metric_transformation {
    name          = "ErrorWarnCount"
    namespace     = var.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# ── Alarm ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "error_warn" {
  alarm_name          = "${var.name_prefix}-error-warn-alarm"
  alarm_description   = "Fires when ERROR/WARN count in app logs exceeds threshold"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.error_warn.metric_transformation[0].name
  namespace           = var.metric_namespace
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.error_count_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [
    "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_name}"
  ]

  tags = var.tags
}

# ── Permission: CloudWatch Alarms → Lambda ────────────────────────────────────
resource "aws_lambda_permission" "cloudwatch_alarm" {
  statement_id  = "AllowCloudWatchAlarmInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.error_warn.arn
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
