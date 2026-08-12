#!/usr/bin/env bash
# Smoke test all 8 petclinic services in a namespace
set -euo pipefail

NAMESPACE="${1:-petclinic-dev}"
FAILURES=0

SERVICES=(config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

echo "=== Smoke test: namespace ${NAMESPACE} ==="
echo ""

echo "--- Deployment readiness ---"
for svc in "${SERVICES[@]}"; do
  DESIRED=$(kubectl get deployment "$svc" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "MISSING")
  if [ "$DESIRED" = "MISSING" ]; then
    fail "$svc deployment not found"
    continue
  fi
  READY=$(kubectl get deployment "$svc" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${READY:-0}" -ge "$DESIRED" ]; then
    pass "$svc (${READY}/${DESIRED} ready)"
  else
    fail "$svc (${READY:-0}/${DESIRED} ready)"
  fi
done

echo ""
echo "--- Config Server health ---"
CONFIG_HEALTH=$(kubectl exec -n "$NAMESPACE" \
  "$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=config-server -o jsonpath='{.items[0].metadata.name}')" \
  -- wget -qO- http://localhost:8888/actuator/health 2>/dev/null || echo '{"status":"DOWN"}')
if echo "$CONFIG_HEALTH" | grep -q '"status":"UP"'; then
  pass "config-server /actuator/health"
else
  fail "config-server /actuator/health: $CONFIG_HEALTH"
fi

echo ""
echo "--- Discovery Server registration ---"
APPS=$(kubectl exec -n "$NAMESPACE" \
  "$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/name=discovery-server -o jsonpath='{.items[0].metadata.name}')" \
  -- wget -qO- http://localhost:8761/eureka/apps 2>/dev/null || echo "")
for svc in api-gateway customers-service visits-service vets-service genai-service admin-server; do
  SVC_UPPER=$(echo "$svc" | tr '[:lower:]-' '[:upper:]_')
  if echo "$APPS" | grep -qi "$SVC_UPPER\|$svc"; then
    pass "$svc registered in Eureka"
  else
    fail "$svc NOT registered in Eureka"
  fi
done

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "All smoke tests PASSED."
  exit 0
else
  echo "${FAILURES} smoke test(s) FAILED."
  exit 1
fi
