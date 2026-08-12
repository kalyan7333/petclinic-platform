#!/usr/bin/env bash
# Install the Kubernetes Metrics Server on EKS.
# PETPLAT-72 — required before any HPA can compute CPU utilisation.
# Without it every HPA reports <unknown>/70% and never scales.
#
# Usage:
#   bash scripts/install-metrics-server.sh [cluster-name]
#
# The cluster-name argument is optional and only used to point kubectl at the
# right cluster first:
#   aws eks update-kubeconfig --name petclinic-dev-eks --region eu-central-1

set -euo pipefail

CHART_VERSION="3.12.1"
APP_NAMESPACE="kube-system"
REGION="eu-central-1"
CLUSTER_NAME="${1:-}"

if [[ -n "${CLUSTER_NAME}" ]]; then
  echo "==> Pointing kubectl at ${CLUSTER_NAME} (${REGION})"
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"
fi

echo "==> Current context: $(kubectl config current-context)"
echo "==> Installing metrics-server chart ${CHART_VERSION} into ${APP_NAMESPACE}"

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
helm repo update metrics-server >/dev/null

# --kubelet-preferred-address-types=InternalIP is required on EKS: the default
# ordering prefers Hostname, which does not resolve for EC2 node names.
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace "${APP_NAMESPACE}" \
  --version "${CHART_VERSION}" \
  --set args="{--kubelet-preferred-address-types=InternalIP}" \
  --set resources.requests.cpu=25m \
  --set resources.requests.memory=64Mi \
  --set resources.limits.cpu=100m \
  --set resources.limits.memory=128Mi \
  --wait --timeout 5m

echo ""
echo "==> Waiting for the metrics API to serve data (can take ~60s)"
for _ in $(seq 1 30); do
  if kubectl top nodes >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

echo ""
echo "==> Verification"
kubectl -n "${APP_NAMESPACE}" get deploy metrics-server
kubectl top nodes
kubectl top pods -n "${APP_NAMESPACE}" | head -5

echo ""
echo "Done. HPAs in ${APP_NAMESPACE} will now report real CPU targets:"
echo "  kubectl get hpa -n ${APP_NAMESPACE}"
