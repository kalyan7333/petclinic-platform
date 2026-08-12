#!/usr/bin/env bash
# Install the External Secrets Operator (ESO) on EKS and apply the petclinic
# ClusterSecretStore + ExternalSecrets.
# PETPLAT-34/35/36
#
# Usage:
#   bash scripts/install-external-secrets.sh <env> <eso-role-arn>
#
# Or take both values straight from Terraform output:
#   bash $(terraform -chdir=terraform/environments/dev output -raw install_external_secrets_command)
#
# Prerequisites:
#   - kubeconfig pointing at the target cluster
#       aws eks update-kubeconfig --name petclinic-<env> --region eu-central-1
#   - Terraform applied (the IRSA role petclinic-<env>-eso-role must exist)
#
# Version note:
#   CHART_VERSION and APP_VERSION share the same numbering for ESO (chart 0.10.5
#   ships app v0.10.5), unlike the LB controller. The CRD bundle URL uses the
#   v-prefixed git tag. Do not move past 0.13.x without migrating the manifests
#   from external-secrets.io/v1beta1 to external-secrets.io/v1.

set -euo pipefail

CHART_VERSION="0.10.5"
APP_VERSION="v0.10.5"
ESO_NAMESPACE="external-secrets"
REGION="eu-central-1"

ENVIRONMENT="${1:?Error: env required (dev). Usage: $0 <env> <eso-role-arn>}"
ROLE_ARN="${2:?Error: eso-role-arn required. Usage: $0 <env> <eso-role-arn>}"

if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "Error: env must be 'dev' — this platform is dev-only, got '${ENVIRONMENT}'" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${REPO_ROOT}/k8s/base/external-secrets"
APP_NAMESPACE="petclinic-${ENVIRONMENT}"

echo "==> Installing External Secrets Operator ${APP_VERSION}"
echo "    Environment  : ${ENVIRONMENT}"
echo "    App namespace: ${APP_NAMESPACE}"
echo "    IRSA role    : ${ROLE_ARN}"
echo ""

# Step 1: CRDs (applied with kubectl so the Helm release never owns them —
# an accidental `helm uninstall` then cannot delete every ExternalSecret).
echo "==> Applying ESO CRDs (${APP_VERSION})..."
kubectl apply --server-side -f \
  "https://raw.githubusercontent.com/external-secrets/external-secrets/${APP_VERSION}/deploy/crds/bundle.yaml"

# Step 2: Namespace + IRSA ServiceAccount.
# The SA is created from git (not by the chart) so the role-arn annotation is
# reviewable and version-controlled.
echo "==> Creating ${ESO_NAMESPACE} namespace and IRSA ServiceAccount..."
kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
sed "s|ROLE_ARN_PLACEHOLDER|${ROLE_ARN}|g" "${MANIFEST_DIR}/serviceaccount.yaml" | kubectl apply -f -

# Step 3: Controller via Helm (ESO publishes no rendered controller manifest).
echo "==> Installing external-secrets controller (chart ${CHART_VERSION})..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace "${ESO_NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --set installCRDs=false \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-secrets-sa \
  --wait \
  --timeout 5m

echo "==> Waiting for ESO deployments to become available..."
kubectl rollout status deployment/external-secrets -n "${ESO_NAMESPACE}" --timeout=5m
kubectl rollout status deployment/external-secrets-webhook -n "${ESO_NAMESPACE}" --timeout=5m

# Step 4: ClusterSecretStore (cluster-scoped).
echo "==> Applying ClusterSecretStore aws-secrets-manager..."
kubectl apply -f "${MANIFEST_DIR}/cluster-secret-store.yaml"

echo "==> Waiting for the ClusterSecretStore to report Ready..."
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=2m

# Step 5: ExternalSecrets for this environment.
if ! kubectl get namespace "${APP_NAMESPACE}" >/dev/null 2>&1; then
  echo "==> Namespace ${APP_NAMESPACE} not found — creating from k8s/base/namespaces.yaml"
  kubectl apply -f "${REPO_ROOT}/k8s/base/namespaces.yaml"
fi

echo "==> Applying ExternalSecrets into ${APP_NAMESPACE}..."
for manifest in rds-credentials openai-api-key; do
  sed "s|ENV_PLACEHOLDER|${ENVIRONMENT}|g" "${MANIFEST_DIR}/${manifest}.yaml" | kubectl apply -f -
done

# Step 6: Verify the K8s Secrets were materialised from Secrets Manager.
echo "==> Waiting for ExternalSecrets to sync..."
sync_failed=0
for es in rds-credentials openai-api-key; do
  if kubectl wait --for=condition=Ready "externalsecret/${es}" \
    -n "${APP_NAMESPACE}" --timeout=2m; then
    echo "    ${es}: synced"
  else
    echo "    ${es}: NOT synced — check 'kubectl describe externalsecret ${es} -n ${APP_NAMESPACE}'" >&2
    sync_failed=1
  fi
done

echo ""
echo "==> Secrets in ${APP_NAMESPACE}:"
kubectl get secret -n "${APP_NAMESPACE}" rds-credentials openai-api-key \
  -o custom-columns='NAME:.metadata.name,TYPE:.type,KEYS:.data' 2>/dev/null || true

if [[ "${sync_failed}" -ne 0 ]]; then
  echo ""
  echo "==> One or more ExternalSecrets failed to sync. Common causes:" >&2
  echo "    - The Secrets Manager secret has no version yet (e.g. openai_api_key" >&2
  echo "      was left empty in tfvars — the secret exists but is empty)." >&2
  echo "    - The IRSA trust policy does not match ${ESO_NAMESPACE}/external-secrets-sa." >&2
  echo "    - The ESO pod started before the SA annotation was applied:" >&2
  echo "        kubectl rollout restart deployment/external-secrets -n ${ESO_NAMESPACE}" >&2
  exit 1
fi

echo ""
echo "==> External Secrets Operator installed and synced successfully."
echo ""
echo "    Verify manually:"
echo "      kubectl get externalsecret -n ${APP_NAMESPACE}"
echo "      kubectl get secret rds-credentials -n ${APP_NAMESPACE} -o jsonpath='{.data.username}' | base64 -d"
echo ""
echo "    Adding a new secret: see docs/secret-rotation.md#adding-a-new-secret"
