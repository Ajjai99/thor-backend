locals {
  # One dashboard, four sections stacked top to bottom: API Gateway, ECS services, Aurora, RDS Proxy.
  # Each section opens with a full-width heading; a section whose inputs are empty is left out and
  # the ones below move up. Every height below is in dashboard grid rows.
  ecs_enabled       = var.ecs_cluster_name != ""
  ecs_service_names = sort(var.ecs_service_names)

  aurora_enabled = var.aurora_cluster_identifier != ""
  proxy_enabled  = var.rds_proxy_name != ""

  api_height    = 15 # heading 1 + charts 6 + requests table 8
  ecs_height    = 7  # heading 1 + charts 6
  aurora_height = 13 # heading 1 + two chart rows of 6
  proxy_height  = 7  # heading 1 + charts 6

  ecs_y    = local.api_height
  aurora_y = local.ecs_y + (local.ecs_enabled ? local.ecs_height : 0)
  proxy_y  = local.aurora_y + (local.aurora_enabled ? local.aurora_height : 0)

  api_dimensions    = ["ApiId", var.api_id, "Stage", var.stage_name]
  aurora_dimensions = ["DBClusterIdentifier", var.aurora_cluster_identifier]
  proxy_dimensions  = ["ProxyName", var.rds_proxy_name]

  # --- API Gateway ------------------------------------------------------------------------------

  api_widgets = [
    {
      type       = "text"
      x          = 0
      y          = 0
      width      = 24
      height     = 1
      properties = { markdown = "## API Gateway" }
    },
    {
      type   = "metric"
      x      = 0
      y      = 1
      width  = 12
      height = 6
      properties = {
        title  = "Requests / 4xx / 5xx"
        region = var.aws_region
        stat   = "Sum"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/ApiGateway", "Count"], local.api_dimensions, [{ label = "Requests" }]),
          concat(["AWS/ApiGateway", "4xx"], local.api_dimensions, [{ label = "4xx", color = "#ff7f0e" }]),
          concat(["AWS/ApiGateway", "5xx"], local.api_dimensions, [{ label = "5xx", color = "#d62728" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 1
      width  = 12
      height = 6
      properties = {
        title  = "Latency (ms)"
        region = var.aws_region
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/ApiGateway", "Latency"], local.api_dimensions, [{ stat = "p50", label = "p50" }]),
          concat(["AWS/ApiGateway", "Latency"], local.api_dimensions, [{ stat = "p99", label = "p99" }]),
          concat(["AWS/ApiGateway", "IntegrationLatency"], local.api_dimensions, [{ stat = "p99", label = "Integration p99" }]),
        ]
      }
    },
    {
      type   = "log"
      x      = 0
      y      = 7
      width  = 24
      height = 8
      properties = {
        title  = "Recent requests (all statuses)"
        region = var.aws_region
        view   = "table"
        query  = <<-EOT
          SOURCE '${var.access_log_group_name}'
          | fields requestTime, httpMethod, path, status, responseLatency, tenant_id, sourceIp, requestId
          | sort @timestamp desc
          | limit 100
        EOT
      }
    },
  ]

  # --- ECS services -----------------------------------------------------------------------------

  ecs_service_metric = {
    for metric in ["CPUUtilization", "MemoryUtilization"] : metric => [
      for service in local.ecs_service_names :
      ["AWS/ECS", metric, "ClusterName", var.ecs_cluster_name, "ServiceName", service, { label = service }]
    ]
  }

  ecs_widgets = [for widget in [
    {
      type       = "text"
      x          = 0
      y          = local.ecs_y
      width      = 24
      height     = 1
      properties = { markdown = "## ECS services" }
    },
    {
      type   = "metric"
      x      = 0
      y      = local.ecs_y + 1
      width  = 8
      height = 6
      properties = {
        title   = "CPU utilization (%)"
        region  = var.aws_region
        stat    = "Average"
        period  = 60
        view    = "timeSeries"
        metrics = local.ecs_service_metric["CPUUtilization"]
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    {
      type   = "metric"
      x      = 8
      y      = local.ecs_y + 1
      width  = 8
      height = 6
      properties = {
        title   = "Memory utilization (%)"
        region  = var.aws_region
        stat    = "Average"
        period  = 60
        view    = "timeSeries"
        metrics = local.ecs_service_metric["MemoryUtilization"]
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    {
      # Container Insights metrics: a running count below desired means tasks are crashing or
      # failing to start.
      type   = "metric"
      x      = 16
      y      = local.ecs_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Running vs desired tasks"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        # concat, not flatten: flatten would also flatten each metric's own array.
        metrics = concat(
          [for service in local.ecs_service_names : ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", service, { label = "${service} running" }]],
          [for service in local.ecs_service_names : ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", var.ecs_cluster_name, "ServiceName", service, { label = "${service} desired" }]],
        )
      }
    },
  ] : widget if local.ecs_enabled]

  # --- Aurora PostgreSQL (Serverless v2) --------------------------------------------------------

  aurora_widgets = [for widget in [
    {
      type       = "text"
      x          = 0
      y          = local.aurora_y
      width      = 24
      height     = 1
      properties = { markdown = "## Aurora PostgreSQL" }
    },
    {
      type   = "metric"
      x      = 0
      y      = local.aurora_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Capacity (ACU) and ACU utilization (%)"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "ServerlessDatabaseCapacity"], local.aurora_dimensions, [{ label = "Capacity (ACU)" }]),
          concat(["AWS/RDS", "ACUUtilization"], local.aurora_dimensions, [{ label = "ACU utilization %", yAxis = "right" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 8
      y      = local.aurora_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "CPU (%) and freeable memory"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "CPUUtilization"], local.aurora_dimensions, [{ label = "CPU %" }]),
          concat(["AWS/RDS", "FreeableMemory"], local.aurora_dimensions, [{ label = "Freeable memory (bytes)", yAxis = "right" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 16
      y      = local.aurora_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Connections and deadlocks"
        region = var.aws_region
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "DatabaseConnections"], local.aurora_dimensions, [{ stat = "Average", label = "Connections" }]),
          # Deadlocks is a rate (Count/Second), so it's averaged, not summed.
          concat(["AWS/RDS", "Deadlocks"], local.aurora_dimensions, [{ stat = "Average", label = "Deadlocks/sec", yAxis = "right", color = "#d62728" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = local.aurora_y + 7
      width  = 12
      height = 6
      properties = {
        title  = "Read / write latency (seconds)"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "ReadLatency"], local.aurora_dimensions, [{ label = "Read" }]),
          concat(["AWS/RDS", "WriteLatency"], local.aurora_dimensions, [{ label = "Write" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = local.aurora_y + 7
      width  = 12
      height = 6
      properties = {
        title  = "Read / write IOPS"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "ReadIOPS"], local.aurora_dimensions, [{ label = "Read IOPS" }]),
          concat(["AWS/RDS", "WriteIOPS"], local.aurora_dimensions, [{ label = "Write IOPS" }]),
        ]
      }
    },
  ] : widget if local.aurora_enabled]

  # --- RDS Proxy --------------------------------------------------------------------------------

  proxy_widgets = [for widget in [
    {
      type       = "text"
      x          = 0
      y          = local.proxy_y
      width      = 24
      height     = 1
      properties = { markdown = "## RDS Proxy" }
    },
    {
      # Client connections far above database connections is the pooling working; database
      # connections near Aurora's limit means the pool is the bottleneck. Sum, not Average: each
      # proxy node reports its own count every minute.
      type   = "metric"
      x      = 0
      y      = local.proxy_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Client vs database connections"
        region = var.aws_region
        stat   = "Sum"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "ClientConnections"], local.proxy_dimensions, [{ label = "Client connections" }]),
          concat(["AWS/RDS", "DatabaseConnections"], local.proxy_dimensions, [{ label = "Database connections" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 8
      y      = local.proxy_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Connection borrow latency (µs)"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "DatabaseConnectionsBorrowLatency"], local.proxy_dimensions, [{ label = "Borrow latency" }]),
        ]
      }
    },
    {
      type   = "metric"
      x      = 16
      y      = local.proxy_y + 1
      width  = 8
      height = 6
      properties = {
        title  = "Query response latency (µs)"
        region = var.aws_region
        stat   = "Average"
        period = 60
        view   = "timeSeries"
        metrics = [
          concat(["AWS/RDS", "QueryDatabaseResponseLatency"], local.proxy_dimensions, [{ label = "Database response latency" }]),
        ]
      }
    },
  ] : widget if local.proxy_enabled]

  widgets = concat(local.api_widgets, local.ecs_widgets, local.aurora_widgets, local.proxy_widgets)
}
