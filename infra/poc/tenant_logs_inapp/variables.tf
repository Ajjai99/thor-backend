variable "aws_region" {
  type        = string
  description = "Region the POC is deployed to (DEV_AWS_REGION, via terragrunt.hcl)"
}

variable "tenant_routing_enabled" {
  type        = bool
  description = "true sets THOR_TENANT_LOG_GROUP_PREFIX (each tenant's logs go to its own group); false leaves it out, so every line goes to stdout as today. Flip between load-test runs to compare."
  default     = true
}

variable "image_tag" {
  type        = string
  description = "Tag of the app/ image pushed to this POC's ECR repository. \"\" (default) creates everything except the ECS service, so the repository exists before the first push."
  default     = ""
}
