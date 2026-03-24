#!/usr/bin/env bash
# rollback.sh — Roll back ECS service to a specific image tag or previous task definition
set -euo pipefail

usage() {
  echo "Usage: $0 <cluster> <service> <task-family> [image-uri]"
  echo ""
  echo "If image-uri is omitted, rolls back to the previous task definition revision."
  echo ""
  echo "Examples:"
  echo "  # Rollback to specific image"
  echo "  $0 nemoclaw-staging nemoclaw-staging-svc nemoclaw-staging 123456789.dkr.ecr.us-east-1.amazonaws.com/nemoclaw:abc1234"
  echo ""
  echo "  # Rollback to previous task definition"
  echo "  $0 nemoclaw-staging nemoclaw-staging-svc nemoclaw-staging"
  exit 1
}

[ $# -lt 3 ] && usage

CLUSTER="$1"
SERVICE="$2"
TASK_FAMILY="$3"
TARGET_IMAGE="${4:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CONTAINER_NAME="${CONTAINER_NAME:-nemoclaw}"

echo "=== NemoClaw Rollback ==="
echo "Cluster:     ${CLUSTER}"
echo "Service:     ${SERVICE}"
echo "Task Family: ${TASK_FAMILY}"

if [ -n "${TARGET_IMAGE}" ]; then
  echo "Target Image: ${TARGET_IMAGE}"
  echo "→ Rolling back to specific image tag..."

  # Get current task definition and update image
  CURRENT_TD=$(aws ecs describe-task-definition \
    --task-definition "${TASK_FAMILY}" \
    --region "${AWS_REGION}" \
    --query taskDefinition)

  NEW_TD=$(echo "${CURRENT_TD}" | python3 -c "
import json, sys
td = json.load(sys.stdin)
for c in td['containerDefinitions']:
    if c['name'] == '${CONTAINER_NAME}':
        old_image = c['image']
        c['image'] = '${TARGET_IMAGE}'
        print(f'  Old image: {old_image}', flush=True, file=sys.stderr)
        print(f'  New image: ${TARGET_IMAGE}', flush=True, file=sys.stderr)
        break
for field in ['taskDefinitionArn','revision','status','requiresAttributes',
              'placementConstraints','compatibilities','registeredAt','registeredBy']:
    td.pop(field, None)
print(json.dumps(td))
")

  NEW_TD_ARN=$(aws ecs register-task-definition \
    --region "${AWS_REGION}" \
    --cli-input-json "${NEW_TD}" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

  echo "→ New task definition: ${NEW_TD_ARN}"

else
  echo "→ Rolling back to previous task definition revision..."

  # Get current revision number
  CURRENT_TD_ARN=$(aws ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${SERVICE}" \
    --region "${AWS_REGION}" \
    --query 'services[0].taskDefinition' \
    --output text)

  CURRENT_REV=$(echo "${CURRENT_TD_ARN}" | grep -o '[0-9]*$')
  PREV_REV=$((CURRENT_REV - 1))

  if [ "${PREV_REV}" -lt 1 ]; then
    echo "❌ No previous revision exists (current is revision 1)" >&2
    exit 1
  fi

  NEW_TD_ARN="${TASK_FAMILY}:${PREV_REV}"
  echo "  Current revision: ${CURRENT_REV}"
  echo "  Rolling back to:  ${PREV_REV}"
fi

# Update service
echo "→ Updating ECS service..."
aws ecs update-service \
  --cluster "${CLUSTER}" \
  --service "${SERVICE}" \
  --task-definition "${NEW_TD_ARN}" \
  --force-new-deployment \
  --region "${AWS_REGION}" \
  > /dev/null

# Wait for stable
echo "→ Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster "${CLUSTER}" \
  --services "${SERVICE}" \
  --region "${AWS_REGION}"

echo "✅ Rollback complete to: ${NEW_TD_ARN}"
