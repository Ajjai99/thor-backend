# auto_deploy redeploys automatically on any route/integration change.
resource "aws_apigatewayv2_stage" "thor-apigw-stage" {
  api_id      = aws_apigatewayv2_api.thor-apigw-api.id
  name        = var.environment
  auto_deploy = true

  # jsonencode quotes every value (fields can be "-", e.g. no integration latency on an authorizer
  # deny), so dashboard queries match status as text. tenant_id comes from Thor.Authorizer's
  # context (AuthorizerContextKeys.TenantId).
  dynamic "access_log_settings" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.access_logs.arn
      format = jsonencode({
        requestId          = "$context.requestId"
        requestTime        = "$context.requestTime"
        httpMethod         = "$context.httpMethod"
        routeKey           = "$context.routeKey"
        path               = "$context.path"
        status             = "$context.status"
        responseLatency    = "$context.responseLatency"
        integrationLatency = "$context.integrationLatency"
        sourceIp           = "$context.identity.sourceIp"
        tenant_id          = "$context.authorizer.tenant_id"
        authorizerError    = "$context.authorizer.error"
        integrationError   = "$context.integrationErrorMessage"
      })
    }
  }

  tags = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
