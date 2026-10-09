# Mirrors modules/api_gateway/alarms.tf, pointed at the POC API. Thresholds default to 1 here so a
# single curl is enough to see each alarm fire.
resource "aws_sns_topic" "api_alarms" {
  name = "${local.name}-api-alarms"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_sns_topic_subscription" "api_alarms_email" {
  count = var.alarm_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.api_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "api" {
  for_each = {
    "4xx" = var.four_xx_alarm_threshold
    "5xx" = var.five_xx_alarm_threshold
  }

  alarm_name          = "${local.name}-api-${each.key}"
  alarm_description   = "POC API returned ${each.value}+ ${each.key} responses in one minute"
  namespace           = "AWS/ApiGateway"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = each.value
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = aws_apigatewayv2_api.api.id
    Stage = aws_apigatewayv2_stage.default.name
  }

  alarm_actions = [aws_sns_topic.api_alarms.arn]
  ok_actions    = [aws_sns_topic.api_alarms.arn]

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# The real module, so testing here also tests the dashboard the dev stack will get.
module "cloudwatch_dashboard" {
  source = "../../src/modules/cloudwatch_dashboard"

  dashboard_name        = "${local.name}-api"
  api_id                = aws_apigatewayv2_api.api.id
  stage_name            = aws_apigatewayv2_stage.default.name
  access_log_group_name = aws_cloudwatch_log_group.access_logs.name
  aws_region            = var.aws_region

  ecs_cluster_name  = aws_ecs_cluster.app.name
  ecs_service_names = [local.app_name]

  aurora_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier
  rds_proxy_name            = aws_db_proxy.rds_proxy.name
}
