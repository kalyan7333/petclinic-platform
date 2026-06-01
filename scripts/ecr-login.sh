#!/usr/bin/env bash
# Authenticate Docker to the Petclinic ECR registry
set -euo pipefail

REGION="${AWS_REGION:-eu-central-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#--region=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--region <region>]" >&2
      exit 1
      ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ECR registry: ${REGISTRY}"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "ECR login successful."
echo "Registry: ${REGISTRY}"
