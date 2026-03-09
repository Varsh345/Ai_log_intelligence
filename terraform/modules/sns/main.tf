# terraform/modules/sns/main.tf

resource "aws_sns_topic" "alerts" {
  name = var.topic_name
  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Explicit policy so AWS does not silently drop email subscriptions
data "aws_iam_policy_document" "alerts" {
  statement {
    sid    = "AllowEmailSubscribeAndReceive"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["sns:Subscribe", "sns:Receive"]
    resources = [aws_sns_topic.alerts.arn]
    condition {
      test     = "StringEquals"
      variable = "sns:Protocol"
      values   = ["email"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}
