data "aws_caller_identity" "current" {}

locals {
  # thor-dev- prefix: the dev role boundary is scoped by resource-name prefix (GOTCHA.md).
  name       = "thor-dev-poc-inapp-logs"
  account_id = data.aws_caller_identity.current.account_id

  # Same layout modules/ecs uses for thor-api / task-api: the service group, and tenant groups
  # under <service group>/tenants/.
  service_log_group = "/ecs/${local.name}/app"
  tenant_log_prefix = "${local.service_log_group}/tenants/"
}

resource "aws_ecr_repository" "app" {
  name         = local.name
  force_delete = true

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ecs_cluster" "poc" {
  name = local.name

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# stdout: the no-tenant and invalid-tenant lines. Tenant groups are NOT declared here — the app
# creates them on first write, so they are outside Terraform state (see cleanup_command).
resource "aws_cloudwatch_log_group" "service" {
  name              = local.service_log_group
  retention_in_days = 7

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# --- iam --------------------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pulls the image and ships stdout via awslogs.
resource "aws_iam_role" "execution" {
  name                 = "${local.name}-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/thor-dev-role-boundary"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: what the app's CloudWatch sink runs as. Same actions and scope as modules/ecs's
# task_tenant_log_groups policy, so this proves that grant under the real boundary.
resource "aws_iam_role" "task" {
  name                 = "${local.name}-task"
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = "arn:aws:iam::${local.account_id}:policy/thor-dev-role-boundary"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy" "task_tenant_log_groups" {
  name = "tenant-log-groups"
  role = aws_iam_role.task.id
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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:${local.tenant_log_prefix}*"
      },
      # The sink lists log groups to see whether a tenant's group exists before creating it.
      # DescribeLogGroups can't be scoped to a group name (it's evaluated against
      # "log-group::log-stream:"), so it's scoped to this account and region instead.
      {
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:*"
      },
    ]
  })
}

# --- task + service (only once an image has been pushed) ---------------------------------------

resource "aws_ecs_task_definition" "app" {
  count = var.image_tag != "" ? 1 : 0

  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # 1 vCPU / 2 GB for the load test (30 tenants x 10 logs/s).
  cpu                = 1024
  memory             = 2048
  execution_role_arn = aws_iam_role.execution.arn
  task_role_arn      = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    # The two env vars modules/ecs sets for services in tenant_log_group_service_keys. Leaving the
    # prefix out is exactly "routing off": everything goes to stdout.
    environment = concat(
      var.tenant_routing_enabled ? [{ name = "THOR_TENANT_LOG_GROUP_PREFIX", value = local.tenant_log_prefix }] : [],
      [{ name = "THOR_AWS_REGION", value = var.aws_region }],
    )

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service.name
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

  name            = local.name
  cluster         = aws_ecs_cluster.poc.id
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

  depends_on = [aws_lb_listener.app]

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# --- internal NLB -------------------------------------------------------------------------------

resource "aws_lb" "app" {
  name               = "thor-dev-poc-inapp-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb.id]

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_lb_target_group" "app" {
  name                 = "thor-dev-poc-inapp-app"
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

# --- API Gateway: every path -> VPC link -> NLB (same path as thor-api) -------------------------

resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_apigatewayv2_vpc_link" "app" {
  name               = "${local.name}-vpclink"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = aws_subnet.public[*].id

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_apigatewayv2_integration" "app" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = aws_lb_listener.app.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.app.id
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.app.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
