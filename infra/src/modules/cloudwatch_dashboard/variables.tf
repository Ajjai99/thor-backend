variable "dashboard_name" {
  type        = string
  description = "CloudWatch dashboard name"
}

variable "aws_region" {
  type        = string
  description = "Region the API, services and database live in"
}

# --- API Gateway --------------------------------------------------------------------------------

variable "api_id" {
  type        = string
  description = "HTTP API (v2) ID — the ApiId dimension of the AWS/ApiGateway metrics"
}

variable "stage_name" {
  type        = string
  description = "API stage name — the Stage dimension of the AWS/ApiGateway metrics"
}

variable "access_log_group_name" {
  type        = string
  description = "Log group the stage writes its JSON access logs to — queried by the request tables"
}

# --- ECS services (section shown only when ecs_cluster_name is set) ----------------------------

variable "ecs_cluster_name" {
  type        = string
  description = "ECS cluster the services run in — the ClusterName dimension of the AWS/ECS and ECS/ContainerInsights metrics. \"\" (default) leaves the ECS section out."
  default     = ""
}

variable "ecs_service_names" {
  type        = list(string)
  description = "ECS service names (the ServiceName dimension): one line per service on each ECS chart."
  default     = []
}

# --- Aurora and RDS Proxy (each section shown only when its name is set) ------------------------

variable "aurora_cluster_identifier" {
  type        = string
  description = "Aurora cluster identifier — the DBClusterIdentifier dimension of the AWS/RDS metrics. \"\" (default) leaves the Aurora section out."
  default     = ""
}

variable "rds_proxy_name" {
  type        = string
  description = "RDS Proxy name — the ProxyName dimension of its AWS/RDS metrics. \"\" (default) leaves the RDS Proxy section out."
  default     = ""
}
