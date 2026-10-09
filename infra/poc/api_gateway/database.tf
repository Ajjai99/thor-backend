# Aurora PostgreSQL Serverless v2 behind RDS Proxy, sized like dev (16.13, 0.5–1 ACU). Throwaway:
# no deletion protection, no final snapshot. The master password is the Aurora-managed Secrets
# Manager secret, which both RDS Proxy and the ECS task read.
resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name}-aurora"
  subnet_ids = aws_subnet.private[*].id

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier          = "${local.name}-aurora"
  engine                      = "aurora-postgresql"
  engine_version              = "16.13"
  database_name               = "thor_poc"
  master_username             = "thor_admin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.aurora.name
  vpc_security_group_ids      = [aws_security_group.aurora.id]
  storage_encrypted           = true
  deletion_protection         = false
  skip_final_snapshot         = true

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  identifier          = "${local.name}-aurora-1"
  cluster_identifier  = aws_rds_cluster.aurora.id
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  instance_class      = "db.serverless"
  publicly_accessible = false

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

locals {
  aurora_secret_arn = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

# --- RDS Proxy ----------------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_proxy" {
  name                 = "${local.name}-rdsproxy-role"
  assume_role_policy   = data.aws_iam_policy_document.rds_proxy_assume.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/thor-dev-role-boundary"

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_iam_role_policy" "rds_proxy" {
  name = "${local.name}-rdsproxy-secret"
  role = aws_iam_role.rds_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.aurora_secret_arn
    }]
  })
}

resource "aws_db_proxy" "rds_proxy" {
  name                   = "${local.name}-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = aws_subnet.private[*].id
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = local.aurora_secret_arn
    iam_auth    = "DISABLED"
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_db_proxy_default_target_group" "rds_proxy" {
  db_proxy_name = aws_db_proxy.rds_proxy.name

  connection_pool_config {
    max_connections_percent = 90
  }
}

resource "aws_db_proxy_target" "aurora" {
  db_proxy_name         = aws_db_proxy.rds_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.rds_proxy.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier

  # The proxy can only register a cluster that has a running instance.
  depends_on = [aws_rds_cluster_instance.aurora]
}
