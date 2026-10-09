# Access logs for the stage. HTTP APIs write these through API Gateway's service-linked role, so no
# CloudWatch role or aws_api_gateway_account is needed (those are REST API only, and the account
# setting is a per-region singleton that dev and qa — sharing an account — would fight over).
resource "aws_cloudwatch_log_group" "access_logs" {
  name              = "/aws/apigateway/${var.service_name}-${var.environment}-access-logs"
  retention_in_days = var.access_log_retention_days
  tags              = var.tags

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
