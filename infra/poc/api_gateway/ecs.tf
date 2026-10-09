# ECS service behind the API, on the same path the real thor-api uses: API Gateway -> VPC link ->
# internal NLB -> Fargate task. The app (app/) logs per tenant through the real Thor.Core and
# reads/writes Aurora through RDS Proxy. Task definition and service are created only once an image
# has been pushed (image_tag), so the ECR repository exists first.
locals {
  app_name              = "${local.name}-app"
  app_log_group         = "/ecs/${local.app_name}"
  app_tenant_log_prefix = "${local.app_log_group}/tenants/"
}

resource "aws_ecr_repository" "app" {
  name         = local.app_name
  force_delete = true

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ecs_cluster" "app" {
  name = local.app_name

  # Running vs desired task counts on the dashboard come from Container Insights.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# stdout: non-tenant lines. Tenant lines go to <this>/tenants/<TenantId>, created by the app.
resource "aws_cloudwatch_log_group" "app" {
  name              = local.app_log_group
  retention_in_days = 7

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# --- iam ----------------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pulls the image, ships stdout, and resolves the DB password secret at task start.
resource "aws_iam_role" "app_execution" {
  name                 = "${local.app_name}-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/thor-dev-role-boundary"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy_attachment" "app_execution" {
  role       = aws_iam_role.app_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "app_execution_secret" {
  name = "${local.app_name}-db-secret"
  role = aws_iam_role.app_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.aurora_secret_arn
    }]
  })
}

# Task role: the per-tenant log groups, same grant as modules/ecs's task_tenant_log_groups.
resource "aws_iam_role" "app_task" {
  name                 = "${local.app_name}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/thor-dev-role-boundary"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy" "app_task_tenant_log_groups" {
  name = "tenant-log-groups"
  role = aws_iam_role.app_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:PutRetentionPolicy",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.app_tenant_log_prefix}*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
    ]
  })
}

# --- internal NLB -------------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "${local.name}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private[*].id
  security_groups    = [aws_security_group.nlb.id]

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.name}-app"
  port                 = 8080
  protocol             = "TCP"
  target_type          = "ip"
  vpc_id               = aws_vpc.poc.id
  deregistration_delay = 10

  health_check {
    protocol = "HTTP"
    path     = "/health"
    port     = "8080"
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# --- task + service -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  count = var.image_tag != "" ? 1 : 0

  family                   = local.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # Same size as thor-api / task-api in dev.
  cpu                = 512
  memory             = 1024
  execution_role_arn = aws_iam_role.app_execution.arn
  task_role_arn      = aws_iam_role.app_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    environment = [
      { name = "THOR_TENANT_LOG_GROUP_PREFIX", value = local.app_tenant_log_prefix },
      { name = "THOR_AWS_REGION", value = var.aws_region },
      { name = "DB_HOST", value = aws_db_proxy.rds_proxy.endpoint },
      { name = "DB_NAME", value = aws_rds_cluster.aurora.database_name },
      { name = "DB_USER", value = aws_rds_cluster.aurora.master_username },
    ]

    secrets = [
      { name = "DB_PASSWORD", valueFrom = "${local.aurora_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ecs_service" "app" {
  count = var.image_tag != "" ? 1 : 0

  name            = local.app_name
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = 8080
  }

  # The proxy must have its target registered before the app's startup query runs.
  depends_on = [aws_lb_listener.app, aws_db_proxy_target.aurora]

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# --- API Gateway route: /app/* -> NLB (the Lambda stays on $default) ----------------------------

resource "aws_apigatewayv2_vpc_link" "app" {
  name               = "${local.name}-vpclink"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = aws_subnet.private[*].id

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Strips the /app prefix, so /app/scan reaches the task as /scan.
resource "aws_apigatewayv2_integration" "app" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.app.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.app.id

  request_parameters = {
    "overwrite:path" = "/$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "app" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /app/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}
