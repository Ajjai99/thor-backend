output "invoke_url" {
  description = "Base URL — curl <invoke_url>/status/500 etc."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${local.name}-api"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

# terragrunt destroy does not remove these — the app creates them on each tenant's first log line.
output "tenant_log_cleanup_command" {
  value = "for g in $(aws logs describe-log-groups --log-group-name-prefix ${local.app_tenant_log_prefix} --query 'logGroups[].logGroupName' --output text); do aws logs delete-log-group --log-group-name \"$g\"; done"
}

output "alarm_sns_topic_arn" {
  value = aws_sns_topic.api_alarms.arn
}

output "access_log_group_name" {
  value = aws_cloudwatch_log_group.access_logs.name
}
