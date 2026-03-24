#!/usr/bin/env bash
# deploy.sh — Update ECS service with a new task definition / image
set -euo pipefail

usage() {
  echo "Usage: $0 <cluster> <service> <task-family> <image-uri>"
  echo ""
  echo "Example:"
  echo "  $0 nemoclaw-staging nemoclaw-staging-svc nemoclaw-staging 123456789.dkr.ecr.us-east-1.amazonaws.com/nemoclaw:abc1234"
  exit 1
}

[ $# -lt 4 ] && usage

CLUSTER="$1"
SERVICE="$2"
TASK_FAMILY="$3"
IMAGE_URI="$4"
AWS_REGION="${AWS_REGION:-us-east-1}"
CONTAINER_NAME="${CONTAINER_NAME:-nemoclaw}"
WAIT_MINUTES="${WAIT_MINUTES:-10}"

echo "=== NemoClaw Deploy Script ==="
echo "Cluster:     ${CLUSTER}"
echo "Service:     ${SERVICE}"
echo "Task Family: ${TASK_FAMILY}"
echo "Image:       ${IMAGE_URI}"

# Get current task definition
echo "→ Fetching current task definition..."
CURRENT_TD=$(aws ecs describe-task-definition \
  --task-definition "${TASK_FAMILY}" \
  --region "${AWS_REGION}" \
  --query taskDefinition)

# Update image in task definition
echo "→ Updating image in task definition..."
NEW_TD=$(echo "${CURRENT_TD}" | python3 -c "
import json, sys
td = json.load(sys.stdin)
for c in td['containerDefinitions']:
    if c['name'] == '${CONTAINER_NAME}':
        c['image'] = '${IMAGE_URI}'
        break

# Remove fields that can't be in register-task-definition
for field in ['taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
              'placementConstraints', 'compatibilities', 'registeredAt', 'registeredBy']:
    td.pop(field, None)

print(json.dumps(td))
")

# Register new task definition
echo "→ Registering new task definition..."
NEW_TD_ARN=$(aws ecs register-task-definition \
  --region "${AWS_REGION}" \
  --cli-input-json "${NEW_TD}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "→ New task definition: ${NEW_TD_ARN}"

# Update ECS service
echo "→ Updating ECS service..."
aws ecs update-service \
  --cluster "${CLUSTER}" \
  --service "${SERVICE}" \
  --task-definition "${NEW_TD_ARN}" \
  --force-new-deployment \
  --region "${AWS_REGION}" \
  > /dev/null

# Wait for stable deployment
echo "→ Waiting for service to stabilize (up to ${WAIT_MINUTES}m)..."
DEADLINE=$((SECONDS + WAIT_MINUTES * 60))
while [ $SECONDS -lt $DEADLINE ]; do
  STATUS=$(aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --region "${AWS_REGION}" \
    --query 'services[0].deployments' \
    --output json)

  RUNNING=$(echo "$STATUS" | python3 -c "
import json, sys
deps = json.load(sys.stdin)
primary = [d for d in deps if d['status'] == 'PRIMARY'][0]
print(primary['runningCount'])
")
  DESIRED=$(echo "$STATUS" | python3 -c "
import json, sys
deps = json.load(sys.stdin)
primary = [d for d in deps if d['status'] == 'PRIMARY'][0]
print(primary['desiredCount'])
")
  COUNT=$(echo "$STATUS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

  echo "  Deployments: ${COUNT} | Running: ${RUNNING}/${DESIRED}"

  if [ "${COUNT}" -eq 1 ] && [ "${RUNNING}" -eq "${DESIRED}" ]; then
    echo "✅ Service stabilized! Running ${RUNNING}/${DESIRED} tasks."
    break
  fi

  sleep 15
done

if [ $SECONDS -ge $DEADLINE ]; then
  echo "❌ Timed out waiting for service stability" >&2
  exit 1
fi

echo "✅ Deploy complete: ${NEW_TD_ARN}"
