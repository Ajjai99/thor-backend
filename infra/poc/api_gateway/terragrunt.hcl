# Standalone POC: an HTTP API with a stub Lambda behind it, plus the same access logs, 4xx/5xx
# alarms and dashboard the real stack uses — to try the monitoring without ECS/NLB/authorizer.
# Deliberately does NOT include root.hcl: that derives the environment from this directory's name
# and runs the dotnet Lambda publish hook, neither of which applies here. Own state key, so
# plan/apply/destroy here never touch the dev stack's state.
locals {
  aws_region   = get_env("DEV_AWS_REGION")
  state_bucket = get_env("TF_STATE_BUCKET")
}

# Terragrunt runs from a copy in .terragrunt-cache. "//" copies all of infra/ into it and runs from
# poc/api_gateway, so monitoring.tf's ../../src/modules/cloudwatch_dashboard still resolves.
terraform {
  source = "${get_terragrunt_dir()}/../..//poc/api_gateway"
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket       = "${local.state_bucket}"
    key          = "thor-poc-api-gateway/terraform.tfstate"
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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
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
      Purpose     = "api-gateway-monitoring-poc"
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
