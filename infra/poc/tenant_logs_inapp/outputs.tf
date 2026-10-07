output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "service_log_group" {
  description = "stdout: only the no-tenant and invalid-tenant lines should appear here"
  value       = aws_cloudwatch_log_group.service.name
}

output "invoke_url" {
  description = "Load-test target: API Gateway -> VPC link -> NLB -> ECS, e.g. curl -X POST <invoke_url>scan?lines=9"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "tenant_log_prefix" {
  value = local.tenant_log_prefix
}

# terragrunt destroy does not remove the tenant groups — the app created them, not Terraform.
output "cleanup_command" {
  value = "for g in $(aws logs describe-log-groups --log-group-name-prefix ${local.tenant_log_prefix} --query 'logGroups[].logGroupName' --output text); do aws logs delete-log-group --log-group-name \"$g\"; done"
}
