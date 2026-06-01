#!/usr/bin/env bash
# Build all 8 petclinic Docker images (ARM64) and push to ECR.
# Requires: aws CLI, docker (with buildx + QEMU for x86 hosts), mvn wrapper in app dir.
#
# Usage:
#   ./scripts/build-and-push.sh --env dev --tag v1.0.0 --app-dir ../spring-petclinic-microservices
#   ./scripts/build-and-push.sh --env dev --tag v1.0.0  # assumes sibling dir

set -euo pipefail

REGION="eu-central-1"
ENV=""
TAG=""
APP_DIR=""
PLATFORM="linux/arm64"

usage() {
  echo "Usage: $0 --env <dev|prod> --tag <image-tag> [--app-dir <path>] [--region <region>]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)      ENV="$2";     shift 2 ;;
    --tag)      TAG="$2";     shift 2 ;;
    --app-dir)  APP_DIR="$2"; shift 2 ;;
    --region)   REGION="$2";  shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$ENV" || -z "$TAG" ]] && usage
[[ "$ENV" != "dev" && "$ENV" != "prod" ]] && { echo "env must be dev or prod" >&2; exit 1; }

# Default app dir: sibling directory named spring-petclinic-microservices
if [[ -z "$APP_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  APP_DIR="${SCRIPT_DIR}/../../spring-petclinic-microservices"
fi

APP_DIR="$(cd "$APP_DIR" && pwd)"
echo "App directory: ${APP_DIR}"
echo "Environment:   ${ENV}"
echo "Image tag:     ${TAG}"
echo "Region:        ${REGION}"
echo "Platform:      ${PLATFORM}"
echo ""

# ECR login
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "==> Logging in to ECR: ${REGISTRY}"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# On x86 hosts, ensure QEMU + buildx are available for ARM64 cross-compilation
if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "arm64" ]]; then
  echo "==> Setting up QEMU + buildx for ARM64 cross-compilation"
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
  docker buildx create --use --name petclinic-builder 2>/dev/null || docker buildx use petclinic-builder
fi

# Service name mapping: maven module suffix -> ECR repo short name
declare -A SERVICES=(
  ["config-server"]="config-server"
  ["discovery-server"]="discovery-server"
  ["api-gateway"]="api-gateway"
  ["customers-service"]="customers-service"
  ["visits-service"]="visits-service"
  ["vets-service"]="vets-service"
  ["genai-service"]="genai-service"
  ["admin-server"]="admin-server"
)

# Build all images using the Maven Spring Boot build plugin
echo "==> Building all 8 images (platform: ${PLATFORM})"
cd "$APP_DIR"
./mvnw clean install -P buildDocker \
  -Dcontainer.platform="${PLATFORM}" \
  --no-transfer-progress

echo ""
echo "==> Tagging and pushing images to ECR"

for SERVICE in "${!SERVICES[@]}"; do
  ECR_REPO="${SERVICES[$SERVICE]}"
  LOCAL_IMAGE="springcommunity/spring-petclinic-${SERVICE}"
  ECR_URI="${REGISTRY}/petclinic-${ENV}/${ECR_REPO}:${TAG}"

  echo "  ${LOCAL_IMAGE} -> ${ECR_URI}"
  docker tag "${LOCAL_IMAGE}" "${ECR_URI}"
  docker push "${ECR_URI}"
done

echo ""
echo "All 8 images pushed successfully."
echo ""
echo "ECR repositories:"
for SERVICE in "${!SERVICES[@]}"; do
  echo "  ${REGISTRY}/petclinic-${ENV}/${SERVICES[$SERVICE]}:${TAG}"
done
