# 4xx/5xx alarms on the stage's built-in metrics. Success traffic has no alarm — it is only visible
# on the dashboard and in the access logs.
resource "aws_sns_topic" "api_alarms" {
  name = "${var.service_name}-${var.environment}-api-alarms"
  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Stays PendingConfirmation until the recipient clicks the link AWS emails them.
resource "aws_sns_topic_subscription" "api_alarms_email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.api_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Missing data is notBreaching: no requests in a minute means no errors, not an unknown state.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.service_name}-${var.environment}-api-5xx"
  alarm_description   = "API Gateway returned ${var.five_xx_alarm_threshold}+ 5xx responses in one minute"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.five_xx_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.thor-apigw-api.id
    Stage = aws_apigatewayv2_stage.thor-apigw-stage.name
  }

  alarm_actions = [aws_sns_topic.api_alarms.arn]
  ok_actions    = [aws_sns_topic.api_alarms.arn]
  tags          = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_cloudwatch_metric_alarm" "api_4xx" {
  alarm_name          = "${var.service_name}-${var.environment}-api-4xx"
  alarm_description   = "API Gateway returned ${var.four_xx_alarm_threshold}+ 4xx responses in one minute"
  namespace           = "AWS/ApiGateway"
  metric_name         = "4xx"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.four_xx_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.thor-apigw-api.id
    Stage = aws_apigatewayv2_stage.thor-apigw-stage.name
  }

  alarm_actions = [aws_sns_topic.api_alarms.arn]
  ok_actions    = [aws_sns_topic.api_alarms.arn]
  tags          = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
