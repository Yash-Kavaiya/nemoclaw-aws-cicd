#!/usr/bin/env bash
# build.sh — Build and push NemoClaw Docker image to ECR
set -euo pipefail

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -r, --region     AWS region (default: us-east-1)"
  echo "  -e, --env        Environment tag (staging|production)"
  echo "  -t, --tag        Image tag (default: git SHA short)"
  echo "  -h, --help       Show this help"
  exit 1
}

AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
GIT_TAG="${GIT_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')}"
ECR_REPO="${ECR_REPOSITORY:-nemoclaw}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)   AWS_REGION="$2"; shift 2 ;;
    -e|--env)      ENVIRONMENT="$2"; shift 2 ;;
    -t|--tag)      GIT_TAG="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

echo "=== NemoClaw Build Script ==="
echo "Region:      ${AWS_REGION}"
echo "Environment: ${ENVIRONMENT}"
echo "Tag:         ${GIT_TAG}"

# Get ECR registry URL
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${ECR_REPO}"

echo "Registry: ${REGISTRY}"

# Authenticate Docker to ECR
echo "→ Authenticating to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${REGISTRY}"

# Build image
echo "→ Building Docker image..."
docker build \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
  -t "${IMAGE}:${GIT_TAG}" \
  -t "${IMAGE}:latest-${ENVIRONMENT}" \
  .

echo "→ Built: ${IMAGE}:${GIT_TAG}"

# Push to ECR
echo "→ Pushing to ECR..."
docker push "${IMAGE}:${GIT_TAG}"
docker push "${IMAGE}:latest-${ENVIRONMENT}"

echo "✅ Build and push complete!"
echo "Image URI: ${IMAGE}:${GIT_TAG}"
