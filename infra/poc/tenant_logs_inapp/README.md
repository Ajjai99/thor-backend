# POC: per-tenant CloudWatch log groups, written by the app

Runs the real `Thor.Core` `UseThorLogging()` with thor-api's real `appsettings.json` and
middleware order (`app/`), behind the same request path thor-api uses:

```
curl -> API Gateway (HTTP API) -> VPC link -> internal NLB -> ECS Fargate task (1 vCPU / 2 GB)
```

The task gets the same env vars and task-role grant that `modules/ecs` gives thor-api and
task-api. No sidecar. `POST /scan?lines=N` writes N log lines for the tenant in the
`X-THOR-TENANT-ID` header, plus one request-completion line.

Every resource carries `ExemptNuke = "true"` (default tags in `terragrunt.hcl`) so the account's
automated cleanup leaves it alone. The tenant log groups the app creates are not tagged.

## Deploy

```bash
cd infra/poc/tenant_logs_inapp
export AWS_PROFILE=aws-app-sbx DEV_AWS_REGION=us-east-1 TF_STATE_BUCKET=thor-terraform-state-877969058937

# 1. Network, API Gateway + VPC link, NLB, ECR, roles, service log group (no ECS service yet)
terragrunt init
terragrunt apply

# 2. Build and push the image (linux/amd64 for Fargate)
REPO=$(terragrunt output -raw ecr_repository_url)
(cd app && dotnet publish -c Release -r linux-x64 --self-contained false -o publish \
  && docker build --platform linux/amd64 -t "$REPO:v1" .)
aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
docker push "$REPO:v1"

# 3. Task definition + service behind the NLB
terragrunt apply -var image_tag=v1
aws ecs wait services-stable --cluster thor-dev-poc-inapp-logs --services thor-dev-poc-inapp-logs
curl "$(terragrunt output -raw invoke_url)health"     # 200
```

`tenant_routing_enabled=false` turns per-tenant log groups off (everything to stdout), for
comparing against today's behaviour.

## Load test

```bash
./loadtest.sh "$(terragrunt output -raw invoke_url)"
```

30 tenants x 1 request/s x 10 logs = 300 logs/s for 10 minutes, through API Gateway. Prints the
request results, then waits 2 minutes and prints the task's CPU and memory for the run window.
`TENANTS`, `LINES`, `DURATION_SECONDS` and `AWS_PROFILE` override the defaults.

Result (2026-10-07): 18,000/18,000 requests OK; 180,000/180,000 lines delivered, 6,000 in each of
30 tenant groups (30-day retention); 0 tenant lines in the service group; 0 errors. CPU 3.09%
average (3.35% peak) of 1 vCPU, memory about 92 MB (99 MB peak). CPU reached 15% only in the first
minute, while the 30 groups were being created.

## Check

```bash
aws logs describe-log-groups --log-group-name-prefix /ecs/thor-dev-poc-inapp-logs \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output table
```

| Log group | Retention | Contents |
|---|---|---|
| `/ecs/thor-dev-poc-inapp-logs/app` | 7 | Lines without a valid tenant ID (plain text) |
| `.../app/tenants/<TenantId>` | 30 | That tenant's lines only (JSON) |

Any `[serilog-selflog]` line in the service group is a CloudWatch failure (IAM, boundary, region).

## Clean up

The tenant groups were created by the app, so `destroy` doesn't remove them:

```bash
eval "$(terragrunt output -raw cleanup_command)"
terragrunt destroy -var image_tag=v1
```

## Lessons for the real rollout

- The task role also needs `logs:DescribeLogGroups` on `log-group:*` (it can't be
  scoped to a group name). Added to `modules/ecs`.
- `thor-<env>-role-boundary` must allow `logs:DescribeLogStreams` and
  `logs:PutRetentionPolicy`. Done for dev (v10); qa and prod still need it.
- Retention is set only when the app creates a group, not on a group that already exists.
- After a permissions fix, a running task recovers by itself; no restart needed.
