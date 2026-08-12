#!/usr/bin/env bash
# PETPLAT-2 — Bootstrap Terraform remote state: S3 bucket + DynamoDB lock table
# Run once before terraform init. Idempotent — safe to re-run.
# Usage: ./scripts/bootstrap-state.sh [--region eu-central-1]

set -euo pipefail

REGION="eu-central-1"
while [[ $# -gt 0 ]]; do
  case $1 in
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "==> Bootstrapping Terraform state backend"
echo "    Region:  ${REGION}"
echo "    Account: ${ACCOUNT_ID}"
echo "    Bucket:  ${BUCKET_NAME}"
echo "    Table:   ${TABLE_NAME}"
echo ""

# ----- S3 bucket -----
if aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>/dev/null; then
  echo "[exists]  S3 bucket: ${BUCKET_NAME}"
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  echo "[created] S3 bucket: ${BUCKET_NAME}"
fi

aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "[configured] S3: versioning=enabled, encryption=AES256, public-access=blocked"

# ----- DynamoDB table -----
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" &>/dev/null; then
  echo "[exists]  DynamoDB table: ${TABLE_NAME}"
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "[created] DynamoDB table: ${TABLE_NAME}"
fi

echo ""
echo "==> Bootstrap complete! Update backend.tf with:"
echo "    bucket         = \"${BUCKET_NAME}\""
echo "    dynamodb_table = \"${TABLE_NAME}\""
echo "    region         = \"${REGION}\""
