#!/usr/bin/env bash
# Load test for the in-app tenant logging POC, through the real request path:
#   curl -> API Gateway -> VPC link -> NLB -> ECS task (Thor.Core per-tenant log groups)
#
# Each tenant sends 1 request/s to POST /scan?lines=LINES. Every request writes LINES log lines plus
# one request-completion line, so the defaults (30 tenants, lines=9, 600 s) produce
# 10 logs/s per tenant = 300 logs/s for 10 minutes.
#
# After the run it waits for ECS metrics and prints the task's CPU and memory for the run window.
#
# Usage:
#   ./loadtest.sh <invoke-url>
#   ./loadtest.sh https://abc123.execute-api.us-east-1.amazonaws.com
#
# Optional settings (environment variables):
#   TENANTS=30  LINES=9  DURATION_SECONDS=600  AWS_PROFILE=aws-app-sbx  CLUSTER=thor-dev-poc-inapp-logs
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <invoke-url>   (get it with: terragrunt output -raw invoke_url)" >&2
  exit 1
fi

URL=${1%/}
TENANTS=${TENANTS:-30}
LINES=${LINES:-9}
DURATION_SECONDS=${DURATION_SECONDS:-600}
CLUSTER=${CLUSTER:-thor-dev-poc-inapp-logs}
export AWS_PROFILE=${AWS_PROFILE:-aws-app-sbx}
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}

RESULTS=$(mktemp -d "${TMPDIR:-/tmp}/thor-loadtest.XXXXXX")

echo "Target:   $URL"
echo "Load:     $TENANTS tenants x 1 request/s x $((LINES + 1)) logs = $((TENANTS * (LINES + 1))) logs/s for ${DURATION_SECONDS}s"
echo "Results:  $RESULTS"

# Fail fast if the API isn't reachable.
status=$(curl -s -o /dev/null -w "%{http_code}" "$URL/health" || true)
if [ "$status" != "200" ]; then
  echo "Health check failed: GET $URL/health returned '$status'" >&2
  exit 1
fi

START=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Started:  $START"

# One serial curl per tenant, all running in parallel. --rate paces each at 1 request/s, and the
# [1-N] range in the URL repeats the request N times with that tenant's header.
for i in $(seq 1 "$TENANTS"); do
  tenant=$(printf "%08x-0000-4000-8000-%012x" "$i" "$i")
  curl -s -o /dev/null --rate 1/s -X POST \
       -H "X-THOR-TENANT-ID: $tenant" \
       -w "%{http_code} %{time_total}\n" \
       "$URL/scan?lines=$LINES&n=[1-$DURATION_SECONDS]" > "$RESULTS/$tenant.txt" 2>&1 &
done
wait

END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Finished: $END"
echo

echo "== Requests"
cat "$RESULTS"/*.txt | awk '{ c[$1]++ } END { for (k in c) printf "  HTTP %s: %d\n", k, c[k] }'
cat "$RESULTS"/*.txt | awk '{ print $2 }' | sort -n | awk '
  { t[NR] = $1 }
  END { printf "  total: %d   latency (s): p50=%.3f  p95=%.3f  p99=%.3f  max=%.3f\n",
        NR, t[int(NR * 0.5)], t[int(NR * 0.95)], t[int(NR * 0.99)], t[NR] }'
echo

# ECS publishes metrics with a 1-2 minute delay.
echo "== ECS task CPU and memory (waiting 2 minutes for metrics...)"
sleep 120
for metric in CPUUtilization MemoryUtilization; do
  aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS --metric-name "$metric" \
    --dimensions Name=ClusterName,Value="$CLUSTER" Name=ServiceName,Value="$CLUSTER" \
    --start-time "$START" --end-time "$END" --period 60 --statistics Average Maximum \
    --query 'Datapoints[].[Average,Maximum]' --output text |
  awk -v m="$metric" '
    { sum += $1; n++; if ($2 > peak) peak = $2 }
    END { if (n) printf "  %-18s avg %.2f%%   peak %.2f%%   (%d one-minute points)\n", m, sum / n, peak, n
          else   printf "  %-18s no datapoints yet - rerun the metrics query in a minute\n", m }'
done
echo
echo "Per-request results are in $RESULTS"
