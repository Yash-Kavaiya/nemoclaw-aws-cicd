#!/usr/bin/env bash
# smoke-test.sh — Poll the ALB health endpoint until passing or timeout
set -euo pipefail

usage() {
  echo "Usage: $0 <base-url> [max-retries]"
  echo ""
  echo "Example:"
  echo "  $0 http://nemoclaw-staging-alb-123.us-east-1.elb.amazonaws.com 30"
  exit 1
}

[ $# -lt 1 ] && usage

BASE_URL="${1%/}"
MAX_RETRIES="${2:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"
HEALTH_PATH="${HEALTH_PATH:-/health}"

HEALTH_URL="${BASE_URL}${HEALTH_PATH}"

echo "=== Smoke Test ==="
echo "URL:     ${HEALTH_URL}"
echo "Retries: ${MAX_RETRIES} × ${RETRY_INTERVAL}s"

for i in $(seq 1 "${MAX_RETRIES}"); do
  echo -n "Attempt ${i}/${MAX_RETRIES}: "

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    --connect-timeout 5 \
    "${HEALTH_URL}" 2>/dev/null || echo "000")

  if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]; then
    echo "✅ HTTP ${HTTP_STATUS} — NemoClaw is healthy!"
    exit 0
  fi

  echo "HTTP ${HTTP_STATUS} — waiting ${RETRY_INTERVAL}s..."
  sleep "${RETRY_INTERVAL}"
done

echo "❌ Smoke test failed after ${MAX_RETRIES} attempts" >&2
exit 1
