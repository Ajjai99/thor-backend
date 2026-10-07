# Small public network across two AZs: the tasks get a public IP so they reach ECR and CloudWatch
# Logs directly (no NAT, no VPC endpoints). Traffic reaches them only through API Gateway -> VPC
# link -> internal NLB, like thor-api; nothing is open to the internet.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  vpc_cidr = "10.98.0.0/24"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "poc" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_internet_gateway" "poc" {
  vpc_id = aws_vpc.poc.id

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.poc.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(local.vpc_cidr, 1, count.index)

  tags = { Name = "${local.name}-public-${local.azs[count.index]}" }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.poc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.poc.id
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- security groups: VPC link -> NLB -> task -------------------------------------------------

resource "aws_security_group" "vpc_link" {
  name        = "${local.name}-vpclink-sg"
  description = "API Gateway VPC link ENIs, egress to the NLB only"
  vpc_id      = aws_vpc.poc.id

  egress {
    description = "To the NLB listener"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_security_group" "nlb" {
  name        = "${local.name}-nlb-sg"
  description = "Internal NLB: from the VPC link, to the tasks"
  vpc_id      = aws_vpc.poc.id

  ingress {
    description     = "From the API Gateway VPC link"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }

  egress {
    description = "To the tasks (traffic and health checks)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_security_group" "task" {
  name        = "${local.name}-task-sg"
  description = "POC in-app tenant logging task: from the NLB only"
  vpc_id      = aws_vpc.poc.id

  ingress {
    description     = "From the NLB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  egress {
    description = "ECR image pull and CloudWatch Logs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Cloud Custodian auto-tags this after creation and an SCP blocks removing it — ignore tags to avoid fighting it.
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}
