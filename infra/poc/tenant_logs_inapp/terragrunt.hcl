# Standalone cloud POC for per-tenant CloudWatch log groups written by the app itself (Thor.Core),
# no sidecar: one Fargate task running app/ with the env vars and task-role grant the real ECS module
# gives thor-api / task-api. Like the other POCs it does NOT include root.hcl and has its own state
# key, so it never touches the dev stack's state.
locals {
  aws_region   = get_env("DEV_AWS_REGION")
  state_bucket = get_env("TF_STATE_BUCKET")
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket       = "${local.state_bucket}"
    key          = "thor-poc-tenant-logs-inapp/terraform.tfstate"
    region       = "${local.aws_region}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      Project     = "thor-platform"
      Environment = "dev"
      ManagedBy   = "terragrunt"
      Purpose     = "tenant-log-groups-inapp-poc"
      # Keeps the account's automated cleanup (arena-nuke) from deleting POC resources.
      ExemptNuke = "true"
    }
  }
}
EOF
}

inputs = {
  aws_region = local.aws_region
}
