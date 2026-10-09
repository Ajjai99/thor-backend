variable "aws_region" {
  type        = string
  description = "Region the POC is deployed to (DEV_AWS_REGION, via terragrunt.hcl)"
}

variable "image_tag" {
  type        = string
  description = "Tag of the app/ image pushed to this POC's ECR repository. \"\" (default) creates everything except the ECS task definition and service, so the repository exists before the first push."
  default     = ""
}

variable "alarm_email" {
  type        = string
  description = "Email subscribed to the alarm SNS topic. \"\" (default) creates the topic with no subscription."
  default     = ""
}

variable "four_xx_alarm_threshold" {
  type        = number
  description = "4xx responses within one minute that put the 4xx alarm into ALARM"
  default     = 1
}

variable "five_xx_alarm_threshold" {
  type        = number
  description = "5xx responses within one minute that put the 5xx alarm into ALARM"
  default     = 1
}
