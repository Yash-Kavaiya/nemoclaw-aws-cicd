#!/usr/bin/env bash
set -euo pipefail

echo "=== NemoClaw AWS Entrypoint ==="
echo "Environment: ${NEMOCLAW_ENV:-staging}"

# Validate required env
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "❌ NVIDIA_API_KEY is not set. Cannot start NemoClaw." >&2
  exit 1
fi

# Non-interactive onboarding for containerized deployment
if [ "${NEMOCLAW_NON_INTERACTIVE:-}" = "1" ]; then
  echo "→ Running in non-interactive (container) mode"
  # Export key for nemoclaw to pick up
  export NVIDIA_API_KEY="${NVIDIA_API_KEY}"

  # Run nemoclaw gateway in foreground
  exec nemoclaw gateway start --port "${PORT:-3000}" --no-tui
else
  exec nemoclaw "$@"
fi
