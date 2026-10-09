#!/usr/bin/env bash
# Traffic for the platform dashboard POC, so every dashboard section has data. All of it goes
# through API Gateway:
#   - TENANTS tenants x 1 request/s to /app/scan  -> tenant log groups, ECS CPU/memory
#   - TENANTS tenants x 1 request/s to /app/db    -> RDS Proxy and Aurora metrics
#   - one /status/500 every 30 s (Lambda route)   -> the API Gateway 5xx line and alarm
#
# Usage:
#   ./traffic.sh <invoke-url>
#   ./traffic.sh https://abc123.execute-api.us-east-1.amazonaws.com
#
# Optional settings (environment variables): TENANTS=10  LINES=4  DURATION_SECONDS=300
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <invoke-url>   (get it with: terragrunt output -raw invoke_url)" >&2
  exit 1
fi

URL=${1%/}
TENANTS=${TENANTS:-10}
LINES=${LINES:-4}
DURATION_SECONDS=${DURATION_SECONDS:-300}
RESULTS=$(mktemp -d "${TMPDIR:-/tmp}/thor-dashboard-traffic.XXXXXX")

echo "Target:   $URL"
echo "Traffic:  $TENANTS tenants x (1 /app/scan + 1 /app/db) per second, plus a /status/500 every 30 s, for ${DURATION_SECONDS}s"

status=$(curl -s -o /dev/null -w "%{http_code}" "$URL/app/health" || true)
if [ "$status" != "200" ]; then
  echo "Health check failed: GET $URL/app/health returned '$status'" >&2
  exit 1
fi

echo "Started:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
for i in $(seq 1 "$TENANTS"); do
  tenant=$(printf "%08x-0000-4000-8000-%012x" "$i" "$i")
  curl -s -o /dev/null --rate 1/s -X POST -H "X-THOR-TENANT-ID: $tenant" -w "scan %{http_code}\n" \
       "$URL/app/scan?lines=$LINES&n=[1-$DURATION_SECONDS]" > "$RESULTS/scan-$tenant.txt" 2>&1 &
  curl -s -o /dev/null --rate 1/s -X POST -H "X-THOR-TENANT-ID: $tenant" -w "db %{http_code}\n" \
       "$URL/app/db?n=[1-$DURATION_SECONDS]" > "$RESULTS/db-$tenant.txt" 2>&1 &
done
curl -s -o /dev/null --rate 2/m -w "status500 %{http_code}\n" \
     "$URL/status/500?n=[1-$(( DURATION_SECONDS / 30 ))]" > "$RESULTS/status500.txt" 2>&1 &
wait
echo "Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "== Responses (endpoint, HTTP status, count)"
cat "$RESULTS"/*.txt | sort | uniq -c | awk '{ printf "  %-10s %s  %d\n", $2, $3, $1 }'
echo
echo "Per-request results are in $RESULTS"
